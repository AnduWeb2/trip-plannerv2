from rest_framework import serializers

class HotelSearchSerializer(serializers.Serializer):
    cityCode = serializers.CharField(max_length=3)
    radius = serializers.IntegerField(default=5)