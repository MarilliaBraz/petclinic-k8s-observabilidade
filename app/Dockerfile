# Atividade 4 - Plataforma de Monitoramento e Observabilidade
# Grupo: Marillia Braz, Lucas Mendes e Pedro Henrique Feitosa
#
# Imagem do Spring PetClinic construida a partir do codigo oficial
# (github.com/spring-projects/spring-petclinic), fixada em um commit para
# que o build seja reproduzivel. A imagem publicada pelo projeto roda como
# binario nativo (GraalVM), e o agente Java do OpenTelemetry precisa de uma
# JVM; por isso a imagem e construida aqui.
#
# O agente OpenTelemetry NAO entra nesta imagem: ele e injetado no pod por
# um initContainer (k8s/app-deployment.yaml), assim a imagem da aplicacao
# continua independente da ferramenta de observabilidade.

ARG PETCLINIC_COMMIT=500158f732419217507c7656904b8e6aa1bcc0d6

FROM maven:3.9.11-eclipse-temurin-21 AS build
ARG PETCLINIC_COMMIT
ADD --keep-git-dir=true https://github.com/spring-projects/spring-petclinic.git#${PETCLINIC_COMMIT} /src
WORKDIR /src
RUN --mount=type=cache,target=/root/.m2 \
    mvn -B -q package -DskipTests \
        -Dcheckstyle.skip=true -Dspring-javaformat.skip=true -Djacoco.skip=true \
 && cp target/spring-petclinic-*.jar /petclinic.jar

FROM eclipse-temurin:21.0.13_9-jre-noble
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin petclinic
COPY --from=build /petclinic.jar /app/petclinic.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/petclinic.jar"]
