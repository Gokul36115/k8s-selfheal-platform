# ---------- Stage 1: BUILD the JAR ----------
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /build
COPY pom.xml .
RUN mvn -q dependency:go-offline
COPY src ./src
RUN mvn -q clean package -DskipTests

# ---------- Stage 2: RUN the app (small image) ----------
FROM eclipse-temurin:17-jre
WORKDIR /app

# Numeric non-root user, so Kubernetes can enforce runAsNonRoot
RUN useradd -r -u 10001 -s /bin/false appuser
COPY --from=build /build/target/*.jar app.jar
USER 10001

EXPOSE 8080

# Container-aware heap sizing + exit on OOM so Kubernetes restarts the pod
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-XX:+ExitOnOutOfMemoryError", "-jar", "app.jar"]
