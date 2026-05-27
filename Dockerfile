# =============================================================
# ESTÁGIO 1 — BUILD
# Usa uma imagem que já tem Maven + JDK 21 para compilar o app
# =============================================================
FROM maven:3.9-eclipse-temurin-21 AS build

# Define /app como diretório de trabalho dentro do container
WORKDIR /app

# Copia APENAS o pom.xml primeiro.
# Motivo: o Docker cacheia cada instrução. Se o pom.xml não mudou,
# o próximo RUN (download de dependências) é pulado no próximo build.
# Isso economiza minutos em cada rebuild quando só o código mudou.
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Agora copia o código-fonte e compila
COPY src ./src
RUN mvn clean package -DskipTests -q
# -DskipTests: não roda testes durante o build da imagem
# -q: modo silencioso (menos log)


# =============================================================
# ESTÁGIO 2 — RUNTIME
# Usa uma imagem mínima: só JRE (sem JDK, sem Maven)
# "alpine" é uma distro Linux tiny (~5 MB), muito usada em containers
# =============================================================
FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Copia o JAR gerado no estágio anterior para esta imagem limpa.
# O "build" é o nome que demos ao estágio 1 (AS build).
# O *.jar funciona porque o Maven gera um único JAR em target/
COPY --from=build /app/target/*.jar app.jar

# Documenta que o container escuta na porta 8080.
# EXPOSE não abre a porta — isso é feito no docker-compose.
# É documentação para quem lê o Dockerfile.
EXPOSE 8080

# Comando executado quando o container sobe.
# -Xmx256m: heap máximo de 256 MB (necessário no plano Railway free)
# -Xms128m: heap inicial de 128 MB
ENTRYPOINT ["java", "-Xmx256m", "-Xms128m", "-jar", "app.jar"]
