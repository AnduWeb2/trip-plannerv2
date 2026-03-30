from django.shortcuts import render
from flights.views import get_amadeus_client
from rest_framework.decorators import api_view
# Create your views here.


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

