FROM maven:3.9.16-eclipse-temurin-21 AS builder

WORKDIR /app
COPY contracts/soap /app/contracts/soap
COPY services/glyph-catalog-java /app/services/glyph-catalog-java
WORKDIR /app/services/glyph-catalog-java
RUN mvn -q -B -DskipTests package

FROM eclipse-temurin:21-jre

WORKDIR /app
COPY --from=builder /app/services/glyph-catalog-java/target/glyph-catalog-java-0.1.0-milestone4.jar /app/glyph-catalog.jar

EXPOSE 8080
ENV GLYPH_CATALOG_PORT=8080
ENV GLYPH_CATALOG_DB_URL=jdbc:h2:file:/app/data/glyph-catalog

ENTRYPOINT ["java", "-jar", "/app/glyph-catalog.jar"]
