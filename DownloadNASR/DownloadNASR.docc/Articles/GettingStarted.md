# Getting Started with DownloadNASR

Configure credentials before running DownloadNASR for the first time.

## Overview

DownloadNASR requires API credentials to upload processed data. These are stored in a git-ignored xcconfig file.

## Setup

### 1. Create Credentials.xcconfig

Copy the template and fill in your credentials:

```bash
cp DownloadNASR/Credentials.xcconfig.template DownloadNASR/Credentials.xcconfig
```

### 2. Configure CloudFlare R2

Required for terrain data uploads. Uses the S3-compatible API.

1. Log into CloudFlare dashboard
2. Go to R2 → Manage R2 API Tokens
3. Create a token with "Object Read & Write" permissions for the sf50-terrain bucket
4. Add to Credentials.xcconfig:
   - `R2_ACCOUNT_ID` - Your CloudFlare account ID
   - `R2_ACCESS_KEY_ID` - The access key ID from the API token
   - `R2_SECRET_ACCESS_KEY` - The secret access key from the API token
   - `R2_BUCKET_NAME` - `sf50-terrain`
   - `R2_PUBLIC_URL` - The public URL from R2 settings

### 3. Configure GitHub Token

Required for nav data uploads.

1. Go to [GitHub Token Settings](https://github.com/settings/personal-access-tokens/new)
2. Create a fine-grained token with:
   - Repository access: Only select repositories → SF50-TOLD/Airport-Data
   - Permissions: Contents → Read and write
3. Add to Credentials.xcconfig:
   - `GITHUB_TOKEN` - The token you created

## Running

After configuration, build and run DownloadNASR. If any required credentials are missing, an alert will show which ones need to be configured.
