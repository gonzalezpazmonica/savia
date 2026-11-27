#!/usr/bin/env bats
# Alerta BinaryArtifacts #60: gradle-wrapper.jar versionado debe estar anclado
# a los checksums OFICIALES de Gradle 8.13 (https://gradle.org/release-checksums/).

WRAPPER_DIR="projects/savia-mobile-android/gradle/wrapper"
PROPS="$WRAPPER_DIR/gradle-wrapper.properties"
JAR="$WRAPPER_DIR/gradle-wrapper.jar"

# Oficial, Gradle 8.13: services.gradle.org/distributions/gradle-8.13-bin.zip.sha256
DIST_SHA="20f1b1176237254a6fc204d8434196fa11a4cfb387567519c61556e8710aed78"
# Oficial, Gradle 8.13: services.gradle.org/distributions/gradle-8.13-wrapper.jar.sha256
JAR_SHA="81a82aaea5abcc8ff68b3dfcb58b3c3c429378efd98e7433460610fecd7ae45f"

@test "distributionUrl apunta a Gradle 8.13 (los checksums de este test son de esa versión)" {
  grep -qE '^distributionUrl=.*gradle-8\.13-bin\.zip$' "$PROPS"
}

@test "distributionSha256Sum existe y es el SHA-256 oficial de gradle-8.13-bin.zip" {
  run grep -E '^distributionSha256Sum=' "$PROPS"
  [ "$status" -eq 0 ]
  [ "$output" = "distributionSha256Sum=$DIST_SHA" ]
}

@test "gradle-wrapper.jar coincide con el checksum oficial del wrapper 8.13" {
  run bash -c "sha256sum '$JAR' | cut -d' ' -f1"
  [ "$status" -eq 0 ]
  [ "$output" = "$JAR_SHA" ]
}
