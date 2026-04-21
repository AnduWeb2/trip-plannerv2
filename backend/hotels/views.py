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
    radius = input_ser.validated_data['radius']

    try:
        amadeus = get_amadeus_client()
        response = amadeus.reference_data.locations.hotels.by_geocode.get(
            latitude=lat,
            longitude=lng,
            radius=radius,
            radiusUnit='KM',
        )
        raw_hotels = [
            {
                'hotelId': h.get('hotelId', ''),
                'name': h.get('name', ''),
                'lat': h.get('geoCode', {}).get('latitude'),
                'lng': h.get('geoCode', {}).get('longitude'),
                'address': ', '.join(h.get('address', {}).get('lines', [])),
                'countryCode': h.get('address', {}).get('countryCode', ''),
            }
            for h in response.data
            if h.get('geoCode', {}).get('latitude') and h.get('geoCode', {}).get('longitude')
        ]
        output = HotelResultSerializer(raw_hotels, many=True)
        return Response({'hotels': output.data})
    except ResponseError as error:
        # Log full details for debugging
        try:
            err_status = error.response.status_code
            err_body = error.response.body
        except Exception:
            err_status = 'unknown'
            err_body = str(error)
        print(f'[hotel_search] Amadeus ResponseError status={err_status} body={err_body}')
        # Amadeus test environment returns 500 for areas with no test data.
        # Return empty list so the map shows gracefully instead of an error.
        if str(err_status) == '500':
            return Response({'hotels': [], 'warning': 'No hotel data available for this area in test environment.'})
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

