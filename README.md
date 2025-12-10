# Stripe Subscription Scraper

A Python script to scrape subscription data from the Stripe API and export it to CSV format.

## Features

- Fetches subscription data from Stripe API using direct HTTP requests
- Extracts customer details (name, email, country, postal code)
- Exports data to both CSV and Excel (.xlsx) formats
- Excel files include formatted headers with styling
- Supports fetching specific subscriptions or all subscriptions
- Handles pagination for large datasets
- Fallback to manual data if API access fails

## Setup

1. Install dependencies:
```bash
pip install -r requirements.txt
```

2. API Key Configuration:
   - The script is pre-configured with the provided key
   - To use a different key, set environment variable:
     ```bash
     export STRIPE_SECRET_KEY=your_key_here
     ```
   - Or edit `main.py` and replace the key in `STRIPE_API_KEY`

## Usage

Run the scraper:
```bash
python main.py
```

The script will:
- Fetch **ALL subscriptions** from your Stripe account
- For each subscription, automatically fetch the associated **customer details**
- Show progress as it processes each subscription and customer
- Extract all relevant data including complete customer information
- Export everything to both `stripe_subscriptions.csv` and `stripe_subscriptions.xlsx`

The Excel file includes:
- Formatted header row with blue background and white text
- Auto-adjusted column widths
- Frozen header row for easy scrolling
- Properly formatted data types

## Important Notes

- The provided key (`rk_live_...`) may be a restricted key with limited permissions
- For full API access, you typically need a Stripe secret key starting with `sk_live_...` or `sk_test_...`
- If the API key doesn't have sufficient permissions, the script will automatically fall back to using the manual data you provided

## Output Format

The CSV file includes the following columns:
- `subscription_id`: Unique subscription identifier
- `object_type`: Object type (e.g., "subscription")
- `status`: Subscription status
- `created`: Creation date (formatted)
- `created_timestamp`: Unix timestamp
- `current_period_start`: Current period start date
- `current_period_end`: Current period end date
- `customer_id`: Customer identifier
- `customer_email`: Customer email address
- `customer_name`: Customer full name
- `customer_country`: Customer country code
- `customer_postal_code`: Customer postal code
- `currency`: Subscription currency
- `amount`: Subscription amount
- `interval`: Billing interval (month, year, etc.)
- `plan_name`: Plan/product name

## Customization

The script by default fetches **all subscriptions** with their customer details. 

To fetch a specific subscription instead, modify the `main()` function:
```python
subscription_id = 'sub_1Scm8EL5YqSpFl3KeJFAFP1g'
subscription = fetch_subscription(subscription_id)
if subscription:
    subscriptions_to_csv([subscription], 'stripe_subscription_single.csv')
    subscriptions_to_excel([subscription], 'stripe_subscription_single.xlsx')
```

## Notes

- Make sure you have the appropriate Stripe API permissions
- The script uses direct HTTP requests to the Stripe API
- Customer address information may not always be available depending on how the customer was created
- The script shows progress indicators while fetching customer details for each subscription
- All customer details are automatically fetched and included in the export files

