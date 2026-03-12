from django.urls import path
from . import views

urlpatterns = [
    path('api/select-destination/<str:param>/', views.select_destination, name="select_destination"),
    path('api/search-flight/', views.search_flight, name="search_flight"),
    path('api/price-offer/', views.price_offer, name="price_offer"),
    path('api/book-flight/', views.book_flight, name="book_flight"),
]
