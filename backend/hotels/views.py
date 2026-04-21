from django.shortcuts import render
from flights.views import get_amadeus_client
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
from amadeus import ResponseError
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

    # Step 1: Google Reverse Geocoding → get city name
    try:
        geo_resp = requests.get(
            'https://maps.googleapis.com/maps/api/geocode/json',
            params={'latlng': f'{lat},{lng}', 'key': GOOGLE_MAPS_API_KEY, 'result_type': 'locality'},
            timeout=5,
        )
        geo_resp.raise_for_status()
        geo_data = geo_resp.json()
        results = geo_data.get('results', [])
        city_name = None
        for result in results:
            for component in result.get('address_components', []):
                if 'locality' in component.get('types', []):
                    city_name = component['long_name']
                    break
            if city_name:
                break
        if not city_name and results:
            # fallback: try first formatted_address word
            city_name = results[0].get('formatted_address', '').split(',')[0].strip()
        print(f'[hotel_search] Reverse geocode → city_name={city_name}')
    except requests.RequestException as e:
        return Response({'error': f'Reverse geocode failed: {e}'}, status=status.HTTP_502_BAD_GATEWAY)

    if not city_name:
        return Response({'hotels': [], 'warning': 'Could not determine city from coordinates.'})

    # Step 2: Amadeus locations search → get IATA city code
    try:
        amadeus = get_amadeus_client()
        loc_response = amadeus.reference_data.locations.get(
            keyword=city_name,
            subType='CITY',
        )
        if not loc_response.data:
            print(f'[hotel_search] No IATA city code found for: {city_name}')
            return Response({'hotels': [], 'warning': f'No Amadeus data for city: {city_name}'})
        city_code = loc_response.data[0]['iataCode']
        print(f'[hotel_search] IATA city code for {city_name} → {city_code}')
    except ResponseError as e:
        print(f'[hotel_search] Amadeus locations error: {e}')
        return Response({'hotels': [], 'warning': 'Could not resolve city code.'})

    # Step 3: Amadeus hotels by city code
    try:
        hotel_response = amadeus.reference_data.locations.hotels.by_city.get(cityCode=city_code)
        print(f'[hotel_search] Amadeus by_city returned {len(hotel_response.data)} hotels for {city_code}')
        if hotel_response.data:
            print(f'[hotel_search] First hotel sample: {hotel_response.data[0]}')
        raw_hotels = []
        for h in hotel_response.data:
            geo = h.get('geoCode') or {}
            hotel_lat = geo.get('latitude')
            hotel_lng = geo.get('longitude')
            if hotel_lat is None or hotel_lng is None:
                continue
            raw_hotels.append({
                'hotelId': h.get('hotelId', ''),
                'name': h.get('name', ''),
                'lat': hotel_lat,
                'lng': hotel_lng,
                'address': ', '.join(h.get('address', {}).get('lines', []) or []),
                'countryCode': h.get('address', {}).get('countryCode', ''),
            })
        print(f'[hotel_search] Returning {len(raw_hotels)} hotels after filtering')
        output = HotelResultSerializer(raw_hotels, many=True)
        return Response({'hotels': output.data})
    except ResponseError as error:
        try:
            err_status = error.response.status_code
            err_body = error.response.body
        except Exception:
            err_status = 'unknown'
            err_body = str(error)
        print(f'[hotel_search] Amadeus by_city ResponseError status={err_status} body={err_body}')
        if str(err_status) == '500':
            return Response({'hotels': [], 'warning': 'No hotel data available for this city in test environment.'})
        return Response({'error': str(error), 'detail': str(err_body)}, status=status.HTTP_400_BAD_REQUEST)
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

