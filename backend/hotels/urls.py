from django.urls import path
from . import views


urlpatterns = [
    path('places/autocomplete/', views.places_autocomplete, name='places-autocomplete'),
    path('places/details/', views.places_details, name='places-details'),
    path('hotels/search/', views.hotel_search, name="hotel-search"),
    path('hotels/offers/', views.hotel_offers, name="hotel-offers"),
    path('hotels/offers/<str:offer_id>/', views.hotel_offer_detail, name="hotel-offer-detail"),
    path('hotels/book/', views.hotel_book, name='hotel-book')
]
