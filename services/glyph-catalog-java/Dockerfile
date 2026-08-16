FROM maven:3.9.16-eclipse-temurin-25 AS builder

WORKDIR /app
COPY contracts/soap /app/contracts/soap
COPY services/glyph-catalog-java /app/services/glyph-catalog-java
WORKDIR /app/services/glyph-catalog-java
RUN mvn -q -B -DskipTests package

# JAVA_VERSION=25 pins the Temurin major line (JVM patch releases flow via the
# tracked eclipse-temurin:25-jre tag; see versions.env).
FROM eclipse-temurin:25-jre

RUN adduser --system --uid 1001 --group --home /nonexistent rghw \
    && mkdir -p /app/data && chown -R rghw:rghw /app

WORKDIR /app
COPY --from=builder /app/services/glyph-catalog-java/target/glyph-catalog-java-0.1.0-milestone4.jar /app/glyph-catalog.jar

EXPOSE 8080
ENV GLYPH_CATALOG_PORT=8080
ENV GLYPH_CATALOG_DB_URL=jdbc:h2:file:/app/data/glyph-catalog

ENTRYPOINT ["java", "-jar", "/app/glyph-catalog.jar"]
