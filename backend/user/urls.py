from rest_framework_simplejwt.views import (TokenObtainPairView,TokenRefreshView,TokenVerifyView)
from django.urls import path
from . import views



urlpatterns = [
    path('api/token/', TokenObtainPairView.as_view(), name="token_obtain_pair"),
    path('api/token/refresh/', TokenRefreshView.as_view(), name="token_refresh"),
    path('api/token/verify/', TokenVerifyView.as_view(), name="token_verify"),
    path('api/register/', views.register, name="user_register"),
    path('api/logout/', views.logout, name="user_logout"),
    path('api/create-traveler/', views.create_traveler, name="create_traveler"),
    path('api/get-travelers', views.get_travelers, name="get_travelers"),
    path('api/update-traveler/<int:pk>/', views.update_traveler, name="update_traveler"),
    path('api/delete-traveler/<int:pk>/', views.delete_traveler, name="delete_traveler"),
    path('api/scan-document/', views.scan_document, name="scan_document"),
]