from django.db import models
from django.conf import settings

class FlightBooking(models.Model):
    

    STATUS_CHOICES = [
        ('CONFIRMED', 'Confirmed'),
        ('CANCELLED', 'Cancelled'),
    ]

    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        
    )
    
    amadeus_order_id = models.CharField(max_length=64, blank=True, default='')
    pnr = models.CharField(max_length=10, blank=True, default='')

    
    airline_name = models.CharField(max_length=100, blank=True, default='')
    origin = models.CharField(max_length=5)
    destination = models.CharField(max_length=5)
    departure_at = models.DateTimeField()
    arrival_at = models.DateTimeField()
    stops = models.PositiveSmallIntegerField(default=0)
    price_total = models.DecimalField(max_digits=10, decimal_places=2)
    price_currency = models.CharField(max_length=5, default='EUR')
    trip_type = models.CharField(max_length=10, default='oneway')
    checkin_link = models.URLField(max_length=500, blank=True, default='')

    
    amadeus_response = models.JSONField(default=dict, blank=True)

    status = models.CharField(max_length=12, choices=STATUS_CHOICES, default='CONFIRMED')
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']

    def __str__(self):
        return f"{self.user.username} — {self.origin}→{self.destination} ({self.pnr})"
