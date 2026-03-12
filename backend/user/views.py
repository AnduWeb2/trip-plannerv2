from django.shortcuts import render
import anthropic
import base64
import json
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from .serializer import UserRegisterSerializer, LogoutSerializer, TravelerProfileSerializer, TravelerProfileGetSerializer, TravelerDocumentSerializer
from .models import TravelerProfile, TravelerDocument
import os

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


@api_view(['POST'])
def scan_document(request):
    data_uri = request.data.get('image')
    if not data_uri:
        return Response({'error': 'No image provided'}, status=400)

    # Parse "data:image/jpeg;base64,<data>"
    try:
        header, b64data = data_uri.split(',', 1)
        media_type = header.split(';')[0].split(':')[1]  # e.g. image/jpeg
    except (ValueError, IndexError):
        return Response({'error': 'Invalid image format'}, status=400)

    api_key = os.environ.get('CLAUDE_API_KEY')
    if not api_key:
        return Response({'error': 'Claude API key not configured'}, status=500)

    try:
        client = anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model='claude-opus-4-5',
            max_tokens=1024,
            messages=[
                {
                    'role': 'user',
                    'content': [
                        {
                            'type': 'image',
                            'source': {
                                'type': 'base64',
                                'media_type': media_type,
                                'data': b64data,
                            },
                        },
                        {
                            'type': 'text',
                            'text': (
                                'Extract the following fields from this identity document image and return ONLY a valid JSON object '
                                'with these exact keys (use null for any field you cannot find):\n'
                                '- first_name (string)\n'
                                '- last_name (string)\n'
                                '- date_of_birth (string, format YYYY-MM-DD)\n'
                                '- gender (string, either "Male" or "Female")\n'
                                '- nationality (string, 2-letter ISO country code, e.g. RO)\n'
                                '- documentType (string, either "PASSPORT" or "ID")\n'
                                '- documentNumber (string)\n'
                                '- issuanceDate (string, format YYYY-MM-DD)\n'
                                '- expiryDate (string, format YYYY-MM-DD)\n'
                                '- issuanceCountry (string, 2-letter ISO country code)\n'
                                '- issuanceLocation (string or null)\n'
                                'Return only the JSON, no explanation.'
                            ),
                        },
                    ],
                }
            ],
        )
        raw = message.content[0].text.strip()
        # Strip markdown code fences if present
        if raw.startswith('```'):
            raw = raw.split('\n', 1)[-1].rsplit('```', 1)[0].strip()
        extracted = json.loads(raw)
        return Response(extracted, status=200)
    except json.JSONDecodeError:
        return Response({'error': 'Claude returned invalid JSON'}, status=502)
    except Exception as e:
        return Response({'error': str(e)}, status=502)