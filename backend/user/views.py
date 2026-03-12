from django.shortcuts import render
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from .serializer import UserRegisterSerializer, LogoutSerializer, TravelerProfileSerializer, TravelerProfileGetSerializer, TravelerDocumentSerializer
from .models import TravelerProfile, TravelerDocument
# Create your views here.

@api_view(['POST'])
@permission_classes([AllowAny])
def register(request):
    data = request.data
    serializer = UserRegisterSerializer(data=data)
    if serializer.is_valid():
        serializer.save()
        return Response({"message": "User registered successfully"}, status=201)
    return Response(serializer.errors, status=400)

@api_view(['POST'])
@permission_classes([AllowAny])
def logout(request):
    data  = request.data
    serializer = LogoutSerializer(data=data)
    if serializer.is_valid():
        serializer.save()
        return Response({"message": "User logged out successfully"}, status=200)
    return Response(serializer.errors, status=400)


@api_view(['POST'])
def create_traveler(request):
    data = request.data
    user = request.user
    doc_field_names = {'documentType', 'documentNumber', 'issuanceDate', 'expiryDate', 'issuanceCountry', 'issuanceLocation'}
    profile_data = {k: v for k, v in data.items() if k not in doc_field_names}
    document_data = {k: v for k, v in data.items() if k in doc_field_names}
    serializer = TravelerProfileSerializer(data=profile_data)
    required_doc_fields = {'documentType', 'documentNumber', 'issuanceDate', 'expiryDate', 'issuanceCountry'}
    missing = required_doc_fields - document_data.keys()
    if missing:
        return Response({'document': 'Document details are required to create a traveler.'}, status=400)
    if serializer.is_valid():
        traveler = serializer.save(user=user)
        doc_serializer = TravelerDocumentSerializer(data=document_data)
        if doc_serializer.is_valid():
            doc_serializer.save(traveler=traveler)
        else:
            traveler.delete()
            return Response(doc_serializer.errors, status=400)
        return Response({'message': 'Traveler created successfully'}, status=201)
    return Response(serializer.errors, status=400)

@api_view(['GET'])
def get_travelers(request):
    user = request.user
    travelers = TravelerProfile.objects.filter(user=user)
    try:
        serializer = TravelerProfileGetSerializer(travelers, many=True)

        return Response(serializer.data, status=200)
    except:
        return Response(serializer.errors, status=400)

@api_view(['PATCH'])
def update_traveler(request, pk):
    user = request.user
    try:
        traveler = TravelerProfile.objects.get(pk=pk, user=user)
    except TravelerProfile.DoesNotExist:
        return Response({'error': 'Traveler not found'}, status=404)
    doc_field_names = {'documentType', 'documentNumber', 'issuanceDate', 'expiryDate', 'issuanceCountry', 'issuanceLocation'}
    profile_data = {k: v for k, v in request.data.items() if k not in doc_field_names}
    document_data = {k: v for k, v in request.data.items() if k in doc_field_names}
    serializer = TravelerProfileSerializer(traveler, data=profile_data, partial=True)
    if serializer.is_valid():
        serializer.save()
        if document_data:
            try:
                doc = traveler.travelerdocument
                doc_serializer = TravelerDocumentSerializer(doc, data=document_data, partial=True)
            except TravelerDocument.DoesNotExist:
                doc_serializer = TravelerDocumentSerializer(data=document_data)
            if doc_serializer.is_valid():
                doc_serializer.save(traveler=traveler)
            else:
                return Response(doc_serializer.errors, status=400)
        return Response({'message': 'Traveler updated successfully'}, status=200)
    return Response(serializer.errors, status=400)

@api_view(['DELETE'])
def delete_traveler(request,pk):
    user = request.user
    try:
        traveler = TravelerProfile.objects.get(pk=pk, user=user) 
    except TravelerProfile.DoesNotExist:
        return Response({"error": "Traveler not found"}, status=404)
    traveler.delete()
    return Response({"message": "Traveler deleted succesfully"}, status=200)