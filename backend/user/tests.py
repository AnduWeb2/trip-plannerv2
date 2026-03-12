from django.contrib.auth import get_user_model
from django.urls import reverse
from rest_framework import status
from rest_framework.test import APITestCase


class AuthRegisterLoginTests(APITestCase):
	def setUp(self):
		self.register_url = reverse('user_register')
		self.token_url = reverse('token_obtain_pair')

		self.valid_register_payload = {
			'username': 'testuser',
			'email': 'testuser@example.com',
			'password': 'S3cureP@ssw0rd123',
			'password2': 'S3cureP@ssw0rd123',
		}

	def test_register_success_creates_user(self):
		response = self.client.post(self.register_url, self.valid_register_payload, format='json')

		self.assertEqual(response.status_code, status.HTTP_201_CREATED)
		self.assertEqual(response.data.get('message'), 'User registered successfully')

		User = get_user_model()
		self.assertTrue(User.objects.filter(username=self.valid_register_payload['username']).exists())

	def test_register_password_mismatch_returns_400(self):
		payload = dict(self.valid_register_payload)
		payload['password2'] = 'DifferentP@ssw0rd123'

		response = self.client.post(self.register_url, payload, format='json')

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn('password', response.data)

	def test_register_duplicate_username_returns_400(self):
		User = get_user_model()
		User.objects.create_user(
			username=self.valid_register_payload['username'],
			email='existing@example.com',
			password='S3cureP@ssw0rd123',
		)

		response = self.client.post(self.register_url, self.valid_register_payload, format='json')

		self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
		self.assertIn('username', response.data)

	def test_login_success_returns_access_and_refresh(self):
		User = get_user_model()
		User.objects.create_user(
			username='loginuser',
			email='loginuser@example.com',
			password='S3cureP@ssw0rd123',
		)

		response = self.client.post(
			self.token_url,
			{'username': 'loginuser', 'password': 'S3cureP@ssw0rd123'},
			format='json',
		)

		self.assertEqual(response.status_code, status.HTTP_200_OK)
		self.assertIn('access', response.data)
		self.assertIn('refresh', response.data)

	def test_login_invalid_credentials_returns_401(self):
		response = self.client.post(
			self.token_url,
			{'username': 'missing', 'password': 'wrong'},
			format='json',
		)

		self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
