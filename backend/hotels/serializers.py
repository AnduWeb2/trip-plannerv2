from rest_framework import serializers


# ─── Places ───────────────────────────────────────────────────────────────────

class PlacesAutocompleteInputSerializer(serializers.Serializer):
    q = serializers.CharField(max_length=200)


class PlaceSuggestionSerializer(serializers.Serializer):
    placeId = serializers.CharField()
    description = serializers.CharField()


class PlacesDetailsInputSerializer(serializers.Serializer):
    place_id = serializers.CharField(max_length=500)


class PlacesDetailsOutputSerializer(serializers.Serializer):
    lat = serializers.FloatField()
    lng = serializers.FloatField()


# ─── Hotels ───────────────────────────────────────────────────────────────────

class HotelSearchInputSerializer(serializers.Serializer):
    lat = serializers.FloatField()
    lng = serializers.FloatField()
    radius = serializers.IntegerField(default=5, min_value=1, max_value=50)


class HotelResultSerializer(serializers.Serializer):
    hotelId = serializers.CharField()
    name = serializers.CharField()
    lat = serializers.FloatField(allow_null=True)
    lng = serializers.FloatField(allow_null=True)
    address = serializers.CharField(allow_blank=True)
    countryCode = serializers.CharField(allow_blank=True)
