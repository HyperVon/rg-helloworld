plugins {
    kotlin("jvm") version "2.4.10"
    kotlin("plugin.serialization") version "2.4.10"
    id("org.jlleitschuh.gradle.ktlint") version "14.2.0"
    application
    jacoco
}

group = "dev.rghw"
version = "0.2.0-milestone11"

repositories {
    mavenCentral()
}

val ktorVersion = "3.5.2"
val kafkaVersion = "4.3.1"
val lettuceVersion = "7.6.0.RELEASE"
val jaxwsVersion = "4.0.5"

val wsimportTools by configurations.creating

dependencies {
    implementation("io.ktor:ktor-server-core:$ktorVersion")
    implementation("io.ktor:ktor-server-netty:$ktorVersion")
    implementation("io.ktor:ktor-server-content-negotiation:$ktorVersion")
    implementation("io.ktor:ktor-serialization-kotlinx-json:$ktorVersion")
    implementation("io.ktor:ktor-server-call-logging:$ktorVersion")
    implementation("io.ktor:ktor-server-default-headers:$ktorVersion")
    implementation("io.ktor:ktor-server-cors:$ktorVersion")
    implementation("io.ktor:ktor-server-status-pages:$ktorVersion")
    implementation("io.ktor:ktor-server-compression:$ktorVersion")
    implementation("org.apache.kafka:kafka-clients:$kafkaVersion")
    implementation("io.lettuce:lettuce-core:$lettuceVersion")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-core:1.11.0")
    implementation("com.sun.xml.ws:jaxws-rt:$jaxwsVersion")
    implementation("jakarta.xml.ws:jakarta.xml.ws-api:4.0.3")
    implementation("jakarta.jws:jakarta.jws-api:3.0.0")
    implementation("io.opentelemetry:opentelemetry-api:1.54.0")
    implementation("io.opentelemetry:opentelemetry-sdk:1.54.0")
    implementation("io.opentelemetry:opentelemetry-sdk-trace:1.54.0")
    implementation("io.opentelemetry:opentelemetry-exporter-otlp:1.54.0")

    wsimportTools("com.sun.xml.ws:jaxws-tools:$jaxwsVersion")

    testImplementation("org.junit.jupiter:junit-jupiter:6.1.2")
    testImplementation("io.ktor:ktor-server-test-host:$ktorVersion")
    testImplementation("io.ktor:ktor-client-cio:$ktorVersion")
    testImplementation("org.apache.kafka:kafka-clients:$kafkaVersion:test")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

ktlint {
    version.set("1.8.0")
    filter {
        exclude("**/generated/**")
    }
}

val generatedSoapDir = layout.buildDirectory.dir("generated/sources/wsimport")
val generatedWsdlDir = layout.buildDirectory.dir("generated/resources/wsdl")

val copySoapContract by tasks.registering(Copy::class) {
    group = "build"
    description = "Copy the SOAP contract into resources for runtime WSDL resolution"
    from(file("../../contracts/soap")) {
        include("glyph-catalog.wsdl", "glyph-catalog.xsd")
    }
    into(generatedWsdlDir)
}

val wsimport by tasks.registering(JavaExec::class) {
    group = "build"
    description = "Generate SOAP client classes from contracts/soap/glyph-catalog.wsdl"
    val wsdlFile = file("../../contracts/soap/glyph-catalog.wsdl")
    val xsdFile = file("../../contracts/soap/glyph-catalog.xsd")
    inputs.file(wsdlFile)
    inputs.file(xsdFile)
    outputs.dir(generatedSoapDir)
    classpath = wsimportTools
    mainClass.set("com.sun.tools.ws.WsImport")
    args(
        "-keep",
        "-s",
        generatedSoapDir.get().asFile.absolutePath,
        "-d",
        generatedSoapDir.get().asFile.absolutePath,
        "-p",
        "dev.rghw.soap.generated",
        "-wsdllocation",
        "/wsdl/glyph-catalog.wsdl",
        wsdlFile.absolutePath,
    )
    doFirst {
        generatedSoapDir.get().asFile.mkdirs()
    }
}

sourceSets.main {
    java.srcDir(generatedSoapDir)
    resources.srcDir(generatedWsdlDir.get().asFile.parentFile)
}

tasks.named("compileJava") {
    dependsOn(wsimport)
}

tasks.named("compileKotlin") {
    dependsOn(wsimport)
}

tasks.named("runKtlintCheckOverMainSourceSet") {
    dependsOn(wsimport)
}

tasks.named("processResources") {
    dependsOn(copySoapContract)
}

java {
    sourceCompatibility = JavaVersion.VERSION_21
    targetCompatibility = JavaVersion.VERSION_21
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21)
    }
}

application {
    mainClass.set("dev.rghw.orchestrator.ApplicationKt")
}

tasks.test {
    useJUnitPlatform()
}

jacoco {
    toolVersion = "0.8.15"
}

tasks.jacocoTestReport {
    dependsOn(tasks.test)
    reports {
        xml.required.set(true)
        html.required.set(true)
    }
    classDirectories.setFrom(
        files(
            classDirectories.files.map {
                fileTree(it) {
                    exclude("dev/rghw/soap/generated/**")
                }
            },
        ),
    )
}

tasks.jacocoTestCoverageVerification {
    dependsOn(tasks.test)
    violationRules {
        rule {
            limit {
                counter = "LINE"
                value = "COVEREDRATIO"
                minimum = "0.90".toBigDecimal()
            }
        }
    }
    classDirectories.setFrom(
        files(
            classDirectories.files.map {
                fileTree(it) {
                    exclude("dev/rghw/soap/generated/**")
                }
            },
        ),
    )
}

tasks.check {
    dependsOn(tasks.jacocoTestReport, tasks.jacocoTestCoverageVerification)
}
