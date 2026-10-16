# ==========================================
# STAGE 1: Build & Package with Maven & Java 21
# ==========================================
FROM maven:3.9.8-eclipse-temurin-21-alpine AS builder

WORKDIR /build

# Cache Maven dependencies by copying pom.xml first
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Copy project source code and build executable jar
COPY src ./src
RUN mvn clean package -DskipTests -B

# ==========================================
# STAGE 2: Lightweight Production Runtime
# ==========================================
FROM eclipse-temurin:21-jre-alpine AS runner

# Install curl for container health checks
RUN apk add --no-cache curl tzdata

# Create dedicated unprivileged user for security compliance
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy the fat jar from builder stage
COPY --from=builder /build/target/*.jar app.jar

# Set ownership to unprivileged user
RUN chown -R appuser:appgroup /app

# Switch to non-root execution
USER appuser

# Expose default HTTP port
EXPOSE 8080

# Environment variables with cloud defaults
ENV PORT=8080 \
    JAVA_OPTS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:+ExitOnOutOfMemoryError -Djava.security.egd=file:/dev/./urandom"

# Healthcheck to verify container readiness
HEALTHCHECK --interval=30s --timeout=5s --start-period=45s --retries=3 \
  CMD curl -f http://localhost:${PORT}/actuator/health || exit 0

# Launch application with optimized container JVM flags
ENTRYPOINT ["sh", "-c", "exec java $JAVA_OPTS -jar app.jar"]
