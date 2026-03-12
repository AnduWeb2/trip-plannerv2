from rest_framework.decorators import api_view
from rest_framework.response import Response
from amadeus import Client, ResponseError, Location
from dotenv import load_dotenv
import os
from datetime import datetime

load_dotenv()
CLIENT_ID = os.environ.get('CLIENT_ID')
CLIENT_SECRET = os.environ.get('CLIENT_SECRET')




def get_amadeus_client():
	return Client(
		client_id=CLIENT_ID,
		client_secret=CLIENT_SECRET
	)


def ensure_pricing_fields(offer, segments):
	if not offer.get('type'):
		offer['type'] = 'flight-offer'
	if not offer.get('id'):
		carrier_code = segments[0].get('carrierCode') if segments else 'XX'
		dep = segments[0]['departure']['at'][:10] if segments else '0000-00-00'
		offer['id'] = f"{carrier_code}-{dep}"
	if not offer.get('validatingAirlineCodes'):
		carrier_code = segments[0].get('carrierCode') if segments else None
		if carrier_code:
			offer['validatingAirlineCodes'] = [carrier_code]
	return offer


def format_datetime(raw):
	if not raw:
		return ''
	try:
		dt = datetime.fromisoformat(raw)
		return dt.strftime('%Y-%m-%d %H:%M')
	except Exception:
		return raw


@api_view(['GET'])
def select_destination(request, param):
	try:
		amadeus = get_amadeus_client()
		response = amadeus.reference_data.locations.get(
			keyword=param,
			subType=Location.ANY,
		)
		normalized = [
			{
				'iataCode': loc.get('iataCode', ''),
				'name': loc.get('name', ''),
				'cityName': loc.get('address', {}).get('cityName', ''),
				'countryName': loc.get('address', {}).get('countryName', ''),
				'subType': loc.get('subType', ''),
			}
			for loc in response.data
			if loc.get('iataCode')
		]
		return Response({'data': normalized}, status=200)
	except ResponseError as error:
		details = None
		try:
			details = error.response.result
		except Exception:
			pass
		return Response({'error': str(error), 'details': details}, status=400)
	except Exception as e:
		return Response({'error': str(e)}, status=500)


@api_view(['GET'])
def search_flight(request):
	origin = request.GET.get('origin')
	destination = request.GET.get('destination')
	departure_date = request.GET.get('departureDate')
	trip_type = request.GET.get('trip_type', 'oneway')
	arrival_date = request.GET.get('arrivalDate')
	adults = request.GET.get('adults', '1')

	missing = []
	if not origin:
		missing.append('origin')
	if not destination:
		missing.append('destination')
	if not departure_date:
		missing.append('departureDate')
	if trip_type == 'round' and not arrival_date:
		missing.append('arrivalDate')
	if missing:
		return Response(
			{'error': 'Missing required query parameters', 'missing': missing},
			status=400
		)

	if trip_type not in {'oneway', 'round'}:
		return Response(
			{'error': 'Invalid trip_type', 'allowed': ['oneway', 'round']},
			status=400
		)

	try:
		adults_int = int(adults)
		if adults_int < 1:
			raise ValueError('adults must be >= 1')
	except (TypeError, ValueError):
		return Response({'error': 'Invalid adults (must be an integer >= 1)'}, status=400)

	# Basic ISO date validation (YYYY-MM-DD)
	from datetime import date
	try:
		date.fromisoformat(departure_date)
		if arrival_date:
			date.fromisoformat(arrival_date)
	except ValueError:
		return Response({'error': 'Invalid date format (expected YYYY-MM-DD)'}, status=400)

	try:
		amadeus = get_amadeus_client()
		amadeus_params = {
			'originLocationCode': origin,
			'destinationLocationCode': destination,
			'departureDate': departure_date,
			'adults': adults_int,
			'nonStop': 'false',
			'max': 3
		}
		if trip_type == 'round' and arrival_date:
			amadeus_params['returnDate'] = arrival_date
		response = amadeus.shopping.flight_offers_search.get(**amadeus_params)
		offers = []
		airline_name_cache = {}
		checkin_link_cache = {}
		for offer in response.data:
			itineraries = offer.get('itineraries', [])
			if not itineraries:
				continue
			segments = itineraries[0].get('segments', [])
			if not segments:
				continue
			departure = segments[0]['departure']
			carrier_code = segments[0].get('carrierCode')
			offer_with_links = offer.copy()
			offer_with_links = ensure_pricing_fields(offer_with_links, segments)

			airline_name = airline_name_cache.get(carrier_code)
			if airline_name is None:
				try:
					airline_response = amadeus.reference_data.airlines.get(airlineCodes=carrier_code)
					airline_data = airline_response.data[0] if airline_response.data else {}
					airline_name = airline_data.get('businessName') or airline_data.get('commonName') or carrier_code
				except ResponseError:
					airline_name = carrier_code
				airline_name_cache[carrier_code] = airline_name

			checkin_link = checkin_link_cache.get(carrier_code)
			if checkin_link is None:
				try:
					checkin_response = amadeus.reference_data.urls.checkin_links.get(airlineCode=carrier_code)
					checkin_data = checkin_response.data[0] if checkin_response.data else {}
					checkin_link = checkin_data.get('href') or checkin_data.get('url')
				except ResponseError:
					checkin_link = None
				checkin_link_cache[carrier_code] = checkin_link

			offer_with_links['airline_name'] = airline_name
			if checkin_link:
				offer_with_links['checkin_link'] = checkin_link
			last_segment = segments[-1]
			offer_with_links['display'] = {
			'origin': departure.get('iataCode', ''),
			'destination': last_segment.get('arrival', {}).get('iataCode', ''),
			'departure': format_datetime(departure.get('at', '')),
			'arrival': format_datetime(last_segment.get('arrival', {}).get('at', '')),
			'stops': len(segments) - 1,
			}
			offers.append(offer_with_links)
		return Response({'offers': offers}, status=200)
	except ResponseError as error:
		details = None
		try:
			details = error.response.result
		except Exception:
			pass
		return Response({'error': str(error), 'details': details}, status=400)
	except Exception as e:
		return Response({'error': str(e)}, status=500)


@api_view(['POST'])
def price_offer(request):
	try:
		amadeus = get_amadeus_client()
		payload = request.data
		data = payload.get('data') if isinstance(payload, dict) else None
		flight_offers = (data.get('flightOffers') or []) if isinstance(data, dict) else []
		if not flight_offers:
			return Response({'error': 'No flight offers provided'}, status=400)

		extra_fields = {'airline_name', 'checkin_link', 'display'}
		cleaned_offers = []
		for offer in flight_offers:
			if not isinstance(offer, dict):
				continue
			offer = {k: v for k, v in offer.items() if k not in extra_fields}
			segments = offer.get('itineraries', [{}])[0].get('segments', [])
			cleaned_offers.append(ensure_pricing_fields(offer, segments))

		if not cleaned_offers:
			return Response({'error': 'No valid flight offers'}, status=400)

		# Pass offers directly — the SDK wraps them in the correct pricing payload
		response = amadeus.shopping.flight_offers.pricing.post(cleaned_offers)
		priced_offers = response.data.get('flightOffers', []) if isinstance(response.data, dict) else []
		priced_offer = priced_offers[0] if priced_offers else {}
		price_data = priced_offer.get('price', {}) if isinstance(priced_offer, dict) else {}
		return Response({
			'offer': priced_offer,
			'display': {
				'price_total': price_data.get('total'),
				'price_currency': price_data.get('currency', 'EUR'),
			}
		}, status=200)
	except ResponseError as error:
		details = None
		try:
			details = error.response.result
		except Exception:
			pass
		return Response({'error': str(error), 'details': details}, status=400)
	except Exception as e:
		return Response({'error': str(e)}, status=500)


@api_view(['POST'])
def book_flight(request):
	try:
		amadeus = get_amadeus_client()
		payload = request.data
		response = amadeus.booking.flight_orders.post(payload)
		return Response(response.data, status=200)
	except ResponseError as error:
		details = None
		try:
			details = error.response.result
		except Exception:
			pass
		return Response({'error': str(error), 'details': details}, status=400)
	except Exception as e:
		return Response({'error': str(e)}, status=500)

