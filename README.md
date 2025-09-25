# Tesla Fleet API - Public Key Host

This is a simple static website to host the Tesla Fleet API public key for registration purposes.

## Files

- `index.html` - Main page with instructions and key display
- `tesla_public_key.pem` - The Tesla Fleet API public key
- `package.json` - Package configuration for Vercel
- `vercel.json` - Vercel deployment configuration

## Deployment

This site is designed to be deployed on Vercel as a static site. The public key will be accessible at `/tesla_public_key.pem`.

## Usage

1. Deploy this site to Vercel
2. Note your domain URL
3. Use `https://yourdomain.vercel.app/tesla_public_key.pem` as the public key URL for Tesla Fleet API registration
4. Complete the Tesla Fleet API registration process
5. Update your Tesla app's allowed origins to use your domain

## Tesla Fleet API Registration

Visit: https://developer.tesla.com/docs/fleet-api/endpoints/partner-endpoints#register
