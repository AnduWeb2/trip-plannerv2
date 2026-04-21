from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
import requests
import os
import math
import time
from .serializers import (
    PlacesAutocompleteInputSerializer,
    PlaceSuggestionSerializer,
    PlacesDetailsInputSerializer,
    PlacesDetailsOutputSerializer,
    HotelSearchInputSerializer,
    HotelResultSerializer,
)

GOOGLE_MAPS_API_KEY = os.environ.get('GOOGLE_MAPS_API_KEY', '')
HOTEL_CACHE_TTL_SECONDS = 300
HOTEL_SEARCH_CACHE = {}
OVERPASS_URLS = [
    'https://overpass.kumi.systems/api/interpreter',
    'https://lz4.overpass-api.de/api/interpreter',
]


def _distance_km(lat1, lng1, lat2, lng2):
    earth_radius_km = 6371.0
    d_lat = math.radians(lat2 - lat1)
    d_lng = math.radians(lng2 - lng1)
    origin_lat = math.radians(lat1)
    target_lat = math.radians(lat2)

    a = (
        math.sin(d_lat / 2) ** 2
        + math.cos(origin_lat) * math.cos(target_lat) * math.sin(d_lng / 2) ** 2
    )
    c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))
    return earth_radius_km * c


def _hotel_cache_key(lat, lng, radius_km):
    return (round(lat, 2), round(lng, 2), radius_km)


def _get_cached_hotels(cache_key, allow_stale=False):
    cached = HOTEL_SEARCH_CACHE.get(cache_key)
    if not cached:
        return None

    age = time.time() - cached['timestamp']
    if age <= HOTEL_CACHE_TTL_SECONDS or allow_stale:
        return cached['hotels']
    return None


def _set_cached_hotels(cache_key, hotels):
    HOTEL_SEARCH_CACHE[cache_key] = {
        'timestamp': time.time(),
        'hotels': hotels,
    }


@api_view(['GET'])
def places_autocomplete(request):
    input_ser = PlacesAutocompleteInputSerializer(data=request.query_params)
    if not input_ser.is_valid():
        return Response(input_ser.errors, status=status.HTTP_400_BAD_REQUEST)

    url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
    params = {
        'input': input_ser.validated_data['q'],
        'key': GOOGLE_MAPS_API_KEY,
        'language': 'ro',
    }
    try:
        resp = requests.get(url, params=params, timeout=5)
        resp.raise_for_status()
        raw = resp.json()
        suggestions = [
            {'placeId': p['place_id'], 'description': p['description']}
            for p in raw.get('predictions', [])
        ]
        output = PlaceSuggestionSerializer(suggestions, many=True)
        return Response({'predictions': output.data})
    except requests.RequestException as e:
        return Response({'error': str(e)}, status=status.HTTP_502_BAD_GATEWAY)


@api_view(['GET'])
def places_details(request):
    input_ser = PlacesDetailsInputSerializer(data=request.query_params)
    if not input_ser.is_valid():
        return Response(input_ser.errors, status=status.HTTP_400_BAD_REQUEST)

    url = 'https://maps.googleapis.com/maps/api/place/details/json'
    params = {
        'place_id': input_ser.validated_data['place_id'],
        'fields': 'geometry',
        'key': GOOGLE_MAPS_API_KEY,
    }
    try:
        resp = requests.get(url, params=params, timeout=5)
        resp.raise_for_status()
        raw = resp.json()
        location = raw.get('result', {}).get('geometry', {}).get('location')
        if not location:
            return Response({'error': 'Location not found.'}, status=status.HTTP_404_NOT_FOUND)
        output = PlacesDetailsOutputSerializer(data={'lat': location['lat'], 'lng': location['lng']})
        output.is_valid()
        return Response(output.data)
    except requests.RequestException as e:
        return Response({'error': str(e)}, status=status.HTTP_502_BAD_GATEWAY)


@api_view(['GET'])
def hotel_search(request):
    input_ser = HotelSearchInputSerializer(data=request.query_params)
    if not input_ser.is_valid():
        return Response(input_ser.errors, status=status.HTTP_400_BAD_REQUEST)

    lat = input_ser.validated_data['lat']
    lng = input_ser.validated_data['lng']
    radius_km = input_ser.validated_data['radius']
    radius_m = radius_km * 1000
    cache_key = _hotel_cache_key(lat, lng, radius_km)

    cached_hotels = _get_cached_hotels(cache_key)
    if cached_hotels is not None:
        return Response({'hotels': cached_hotels, 'cached': True})

    overpass_query = f'''
[out:json][timeout:8];
(
  node["tourism"~"hotel|hostel|motel|guest_house|apartment"]["name"](around:{radius_m},{lat},{lng});
  way["tourism"~"hotel|hostel|motel|guest_house|apartment"]["name"](around:{radius_m},{lat},{lng});
);
out center 80;
'''

    try:
        elements = []
        last_error = None

        for overpass_url in OVERPASS_URLS:
            try:
                response = requests.post(
                    overpass_url,
                    data={'data': overpass_query},
                    headers={
                        'Accept': 'application/json',
                        'User-Agent': 'trip-plannerv2/1.0',
                    },
                    timeout=10,
                )
                response.raise_for_status()
                elements = response.json().get('elements', [])
                print(
                    f'[hotel_search] Overpass returned {len(elements)} elements '
                    f'from {overpass_url} for lat={lat} lng={lng} radius={radius_km}km'
                )
                break
            except requests.RequestException as e:
                last_error = e
                print(f'[hotel_search] Overpass request failed for {overpass_url}: {e}')

        if last_error and not elements:
            stale_hotels = _get_cached_hotels(cache_key, allow_stale=True)
            if stale_hotels is not None:
                return Response({'hotels': stale_hotels, 'cached': True, 'warning': 'Serving cached hotel results.'})
            raise last_error

        hotels_by_id = {}
        for element in elements:
            tags = element.get('tags') or {}
            if element.get('type') == 'node':
                hotel_lat = element.get('lat')
                hotel_lng = element.get('lon')
            else:
                center = element.get('center') or {}
                hotel_lat = center.get('lat')
                hotel_lng = center.get('lon')

            if hotel_lat is None or hotel_lng is None:
                continue

            hotel_id = str(element.get('id', ''))
            name = (tags.get('name') or tags.get('name:en') or '').strip()
            if not name:
                continue

            distance = _distance_km(lat, lng, hotel_lat, hotel_lng)
            if distance > radius_km:
                continue

            address_parts = [
                tags.get('addr:street', '').strip(),
                tags.get('addr:housenumber', '').strip(),
                tags.get('addr:city', '').strip(),
            ]
            address = ', '.join(part for part in address_parts if part)

            hotels_by_id[hotel_id] = {
                'hotelId': hotel_id,
                'name': name,
                'lat': hotel_lat,
                'lng': hotel_lng,
                'address': address,
                'countryCode': tags.get('addr:country', '').strip(),
                'distanceKm': distance,
            }

        raw_hotels = sorted(hotels_by_id.values(), key=lambda hotel: hotel['distanceKm'])
        for hotel in raw_hotels:
            hotel.pop('distanceKm', None)
        _set_cached_hotels(cache_key, raw_hotels)
        output = HotelResultSerializer(raw_hotels, many=True)
        return Response({'hotels': output.data})
    except requests.RequestException as e:
        print(f'[hotel_search] Overpass request error: {e}')
        return Response({'error': str(e)}, status=status.HTTP_502_BAD_GATEWAY)
    except Exception as e:
        print(f'[hotel_search] Unexpected error: {e}')
        return Response({'error': str(e)}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

@api_view(['GET'])
def hotel_offers(request):
    pass

@api_view(['GET'])
def hotel_offer_detail(request, offer_id):
    pass

@api_view(['POST'])
def hotel_book(request):
    pass

