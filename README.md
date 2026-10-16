# Production All-in-One Donation & Crowdfunding Platform

A robust, enterprise-grade donation and crowdfunding backend built with **Java 21**, **Spring Boot 3.3+**, **PostgreSQL**, and **Razorpay**. Designed for deployment to cloud container platforms (**Render / Railway**) backed by serverless PostgreSQL (**Neon**).

---

## Architecture Highlights
- **Stateless Security**: Spring Security 6 with JJWT 0.12.x tokens and dynamic CORS binding for cloud frontends (Vercel, Netlify).
- **Payment Lifecycle Integrity**: Cryptographic HMAC-SHA256 signature verification using Razorpay Java SDK.
- **Concurrency & Race Condition Prevention**: JPA `@Version` Optimistic Locking on Campaign totals coupled with `@Retryable` backoff prevents lost updates under high concurrent donation volume.
- **Neon Cloud Resilience**: HikariCP connection pool tuned specifically for Neon serverless PostgreSQL keepalives and idle suspensions.
- **Containerization**: Multi-stage Docker build producing an unprivileged, secure JRE 21 micro-container.

---

## Environment Variables Reference

| Variable | Description | Default / Example |
| :--- | :--- | :--- |
| `PORT` | Web server port | `8080` |
| `SPRING_DATASOURCE_URL` | PostgreSQL JDBC connection URL | `jdbc:postgresql://ep-xyz.us-east-2.aws.neon.tech/donation_db?sslmode=require` |
| `SPRING_DATASOURCE_USERNAME` | Database username | `neondb_owner` |
| `SPRING_DATASOURCE_PASSWORD` | Database password | `your_secret_password` |
| `JWT_SECRET` | 512-bit / 64-char secret key for JJWT signing | `404E635266556A586E3272357538782F413F4428472B4B6250645367566B5970` |
| `FRONTEND_URL` | Comma-separated allowed CORS origins | `https://your-frontend.vercel.app,http://localhost:3000` |
| `RAZORPAY_KEY_ID` | Razorpay Merchant Key ID | `rzp_test_...` or `rzp_live_...` |
| `RAZORPAY_KEY_SECRET` | Razorpay Merchant Secret Key | `your_razorpay_secret` |
| `HIBERNATE_DDL_AUTO` | Hibernate schema update mode | `update` (or `validate`) |

---

## API Endpoints Overview

### Authentication (`/api/v1/auth`)
- `POST /api/v1/auth/register` - Create account (`ROLE_USER`, `ROLE_CAMPAIGN_OWNER`)
- `POST /api/v1/auth/login` - Authenticate and obtain Bearer JWT

### Campaigns (`/api/v1/campaigns`)
- `GET /api/v1/campaigns` - List active campaigns with real-time funded percentage (Public)
- `GET /api/v1/campaigns/paged` - Paginated active campaigns (Public)
- `GET /api/v1/campaigns/{id}` - Campaign details by ID (Public)
- `POST /api/v1/campaigns` - Create new campaign (Authenticated `Bearer <token>`)

### Donations (`/api/v1/donations`)
- `POST /api/v1/donations/order` - Initiate Razorpay order and register `INITIATED` donation (Public)
- `POST /api/v1/donations/verify` - Verify HMAC signature, transition to `SUCCESS`, atomically increment campaign funds (Public)
- `GET /api/v1/donations/campaign/{campaignId}` - List verified donations for a campaign (Public)

---

## Local Development & Docker Instructions

### 1. Build and Run Locally
```bash
mvn clean package
java -jar target/all-in-one-donation-system-1.0.0.jar
```

### 2. Build Docker Container
```bash
docker build -t donation-platform:latest .
docker run -p 8080:8080 \
  -e SPRING_DATASOURCE_URL="jdbc:postgresql://<neon-host>/neondb?sslmode=require" \
  -e SPRING_DATASOURCE_USERNAME="<neon-user>" \
  -e SPRING_DATASOURCE_PASSWORD="<neon-pass>" \
  -e RAZORPAY_KEY_ID="rzp_test_xxx" \
  -e RAZORPAY_KEY_SECRET="xxx" \
  donation-platform:latest
```

### 3. Testing with Frontend Checkout Harness
Open `test-checkout.html` in your browser (via VS Code Live Server or static file), enter your active Campaign UUID, and test the full live Razorpay checkout lifecycle.
