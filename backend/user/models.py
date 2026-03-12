from django.db import models
from django.contrib.auth.models import AbstractUser
# Create your models here.

class User(AbstractUser):
    email = models.EmailField(max_length=60)
    username = models.CharField(max_length=25, unique=True)
    

    def __str__(self):
        return f"{self.username} || {self.email}"


class TravelerProfile(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE)
    first_name = models.CharField(max_length=50)
    last_name = models.CharField(max_length=50)
    date_of_birth = models.DateField()
    gender = models.CharField(max_length=10)
    phone_country_code = models.CharField(max_length=4)
    phone_number = models.CharField(max_length=16)
    nationality = models.CharField(max_length=2)

    def __str__(self):
        return f"{self.user.username} - {self.first_name} {self.last_name}"
    
class TravelerDocument(models.Model):

    PASSPORT = "PASSPORT"
    ID = "ID"
    DOCUMENT_TYPES = [
        (PASSPORT, "Passport"),
        (ID, "National ID")
    ]

    traveler = models.OneToOneField(TravelerProfile, on_delete=models.CASCADE)
    documentType = models.CharField(max_length=10, choices=DOCUMENT_TYPES)
    issuanceDate = models.DateField()
    expiryDate = models.DateField()
    issuanceCountry = models.CharField(max_length=2)
    issuanceLocation = models.CharField(max_length=30,null=True, blank=True)
    documentNumber = models.CharField(max_length=30)