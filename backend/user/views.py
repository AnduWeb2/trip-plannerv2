from django.shortcuts import render
from google import genai
from google.genai import errors, types
import base64
import json
import pycountry
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from .serializer import UserRegisterSerializer, LogoutSerializer, TravelerProfileSerializer, TravelerProfileGetSerializer, TravelerDocumentSerializer
from .models import TravelerProfile, TravelerDocument
import os


def normalize_country_code(value):
    if not value or not isinstance(value, str):
        return value

    code = value.strip().upper()
    if len(code) == 2:
        return code

    if len(code) == 3:
        country = pycountry.countries.get(alpha_3=code)
        if country:
            return country.alpha_2

    return code


def normalize_scan_document_payload(payload):
    if not isinstance(payload, dict):
        return payload

    for field in ('nationality', 'issuanceCountry'):
        payload[field] = normalize_country_code(payload.get(field))

    return payload

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


def _parse_data_uri(data_uri):
    """Parse a data URI and return (image_bytes, media_type)."""
    header, b64data = data_uri.split(',', 1)
    media_type = header.split(';')[0].split(':')[1]
    return base64.b64decode(b64data), media_type


@api_view(['POST'])
def scan_document(request):
    # Accept both old single-image format and new front/back format
    front_uri = request.data.get('front_image') or request.data.get('image')
    back_uri = request.data.get('back_image')

    if not front_uri:
        return Response({'error': 'No image provided'}, status=400)

    try:
        front_bytes, front_mime = _parse_data_uri(front_uri)
    except (ValueError, IndexError):
        return Response({'error': 'Invalid front image format'}, status=400)

    back_bytes, back_mime = None, None
    if back_uri:
        try:
            back_bytes, back_mime = _parse_data_uri(back_uri)
        except (ValueError, IndexError):
            return Response({'error': 'Invalid back image format'}, status=400)

    api_key = os.environ.get('GEMINI_API_KEY')
    if not api_key:
        return Response({'error': 'Gemini API key not configured'}, status=500)

    schema = {
        'type': 'OBJECT',
        'properties': {
            'first_name': {'type': 'STRING', 'nullable': True},
            'last_name': {'type': 'STRING', 'nullable': True},
            'date_of_birth': {'type': 'STRING', 'nullable': True},
            'gender': {'type': 'STRING', 'nullable': True},
            'nationality': {'type': 'STRING', 'nullable': True},
            'documentType': {'type': 'STRING', 'nullable': True},
            'documentNumber': {'type': 'STRING', 'nullable': True},
            'issuanceDate': {'type': 'STRING', 'nullable': True},
            'expiryDate': {'type': 'STRING', 'nullable': True},
            'issuanceCountry': {'type': 'STRING', 'nullable': True},
            'issuanceLocation': {'type': 'STRING', 'nullable': True},
        },
        'required': [
            'first_name',
            'last_name',
            'date_of_birth',
            'gender',
            'nationality',
            'documentType',
            'documentNumber',
            'issuanceDate',
            'expiryDate',
            'issuanceCountry',
            'issuanceLocation',
        ],
    }

    # Build the image parts for the Gemini request
    image_parts = [
        types.Part.from_bytes(data=front_bytes, mime_type=front_mime),
    ]
    if back_bytes and back_mime:
        image_parts.append(
            types.Part.from_bytes(data=back_bytes, mime_type=back_mime),
        )

    has_back = back_bytes is not None
    prompt = (
        'Extract traveler identity document data from the provided image(s). '
        + ('The first image is the FRONT of the document and the second image is the BACK. '
           'Combine information from both sides into a single result. '
           if has_back else '')
        + 'Return country codes strictly as ISO 3166-1 alpha-2 codes only, like RO, FR, US. '
        'Never return 3-letter country codes like ROU or USA. '
        'Dates must be in YYYY-MM-DD format. '
        'Set missing or uncertain fields to null.'
    )

    try:
        with genai.Client(api_key=api_key) as client:
            response = client.models.generate_content(
                model='gemini-2.5-flash',
                contents=[*image_parts, prompt],
                config=types.GenerateContentConfig(
                    response_mime_type='application/json',
                    response_schema=schema,
                    temperature=0,
                ),
            )

        if response.parsed is not None:
            return Response(normalize_scan_document_payload(response.parsed), status=200)

        raw = (response.text or '').strip()
        if raw.startswith('```'):
            raw = raw.split('\n', 1)[-1].rsplit('```', 1)[0].strip()

        extracted = json.loads(raw)
        return Response(normalize_scan_document_payload(extracted), status=200)
    except json.JSONDecodeError:
        return Response({'error': 'Gemini returned invalid JSON'}, status=502)
    except errors.APIError as e:
        status_code = e.code if isinstance(e.code, int) else 502
        return Response({'error': e.message}, status=status_code)
    except Exception as e:
        return Response({'error': str(e)}, status=502)