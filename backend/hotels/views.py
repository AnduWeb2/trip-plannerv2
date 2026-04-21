from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
import requests
import os
from .serializers import (
    PlacesAutocompleteInputSerializer,
    PlaceSuggestionSerializer,
    PlacesDetailsInputSerializer,
    PlacesDetailsOutputSerializer,
    HotelSearchInputSerializer,
    HotelResultSerializer,
)

GOOGLE_MAPS_API_KEY = os.environ.get('GOOGLE_MAPS_API_KEY', '')


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

    overpass_query = f'''
[out:json][timeout:20];
(
  node["tourism"~"hotel|hostel|motel|guest_house|apartment"](around:{radius_m},{lat},{lng});
  way["tourism"~"hotel|hostel|motel|guest_house|apartment"](around:{radius_m},{lat},{lng});
  relation["tourism"~"hotel|hostel|motel|guest_house|apartment"](around:{radius_m},{lat},{lng});
);
out center 150;
'''

    try:
        elements = []
        overpass_urls = [
            'https://overpass-api.de/api/interpreter',
            'https://overpass.kumi.systems/api/interpreter',
        ]
        last_error = None

        for overpass_url in overpass_urls:
            try:
                response = requests.post(
                    overpass_url,
                    data={'data': overpass_query},
                    timeout=25,
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
            name = tags.get('name') or tags.get('name:en') or 'Hotel'
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
            }

        raw_hotels = list(hotels_by_id.values())
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

