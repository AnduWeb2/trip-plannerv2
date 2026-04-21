from django.shortcuts import render
from flights.views import get_amadeus_client
from rest_framework.decorators import api_view
from rest_framework.response import Response
from rest_framework import status
import requests
import os

GOOGLE_MAPS_API_KEY = os.environ.get('GOOGLE_MAPS_API_KEY', '')


@api_view(['GET'])
def places_autocomplete(request):
    
    input_text = request.query_params.get('q', '').strip()
    if not input_text:
        return Response({'error': 'Query param "q" is required.'}, status=status.HTTP_400_BAD_REQUEST)

    url = 'https://maps.googleapis.com/maps/api/place/autocomplete/json'
    params = {
        'input': input_text,
        'key': GOOGLE_MAPS_API_KEY,
        'language': 'ro',
    }
    try:
        resp = requests.get(url, params=params, timeout=5)
        resp.raise_for_status()
        data = resp.json()
        predictions = [
            {'placeId': p['place_id'], 'description': p['description']}
            for p in data.get('predictions', [])
        ]
        return Response({'predictions': predictions})
    except requests.RequestException as e:
        return Response({'error': str(e)}, status=status.HTTP_502_BAD_GATEWAY)


@api_view(['GET'])
def places_details(request):
    
    place_id = request.query_params.get('place_id', '').strip()
    if not place_id:
        return Response({'error': 'Query param "place_id" is required.'}, status=status.HTTP_400_BAD_REQUEST)

    url = 'https://maps.googleapis.com/maps/api/place/details/json'
    params = {
        'place_id': place_id,
        'fields': 'geometry',
        'key': GOOGLE_MAPS_API_KEY,
    }
    try:
        resp = requests.get(url, params=params, timeout=5)
        resp.raise_for_status()
        data = resp.json()
        location = data.get('result', {}).get('geometry', {}).get('location')
        if not location:
            return Response({'error': 'Location not found.'}, status=status.HTTP_404_NOT_FOUND)
        return Response({'lat': location['lat'], 'lng': location['lng']})
    except requests.RequestException as e:
        return Response({'error': str(e)}, status=status.HTTP_502_BAD_GATEWAY)


@api_view(['GET'])
def hotel_search(request):
    pass

@api_view(['GET'])
def hotel_offers(request):
    pass

@api_view(['GET'])
def hotel_offer_detail(request, offer_id):
    pass

@api_view(['POST'])
def hotel_book(request):
    pass

