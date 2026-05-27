# Web Services com Spring Boot, JPA e Hibernate

Projeto de estudo desenvolvido no curso **Java COMPLETO** de Nelio Alves. Implementa um web service RESTful de e-commerce usando Spring Boot 3.5.10, JPA/Hibernate para ORM e H2 como banco de dados em memória.

---

## Tecnologias

| Tecnologia | Versão |
|---|---|
| Java | 21 |
| Spring Boot | 3.5.10 |
| Spring Data JPA / Hibernate | (via Spring Boot) |
| H2 Database (perfil `test`) | (via Spring Boot) |
| PostgreSQL (perfil `prod`) | 16 |
| Docker / Docker Compose | — |
| Maven | (wrapper incluso) |

---

## Como Executar

```powershell
# Iniciar a aplicação
.\mvnw.cmd spring-boot:run

# Gerar JAR
.\mvnw.cmd clean package

# Executar testes
.\mvnw.cmd test
```

A aplicação sobe em `http://localhost:8080`.  
Console H2 disponível em `http://localhost:8080/h2-console` com JDBC URL `jdbc:h2:mem:testdb`.

---

## Arquitetura em Camadas

O projeto segue a arquitetura em 4 camadas sob o pacote `com.educandoweb.course`:

```
┌─────────────────────────────────┐
│   resources/  (REST Controllers) │  ← Recebe requisições HTTP
├─────────────────────────────────┤
│   services/   (Regras de negócio)│  ← Lógica da aplicação + exceções de domínio
├─────────────────────────────────┤
│   repositories/ (Acesso a dados) │  ← Spring Data JPA
├─────────────────────────────────┤
│   entities/   (Modelo de domínio)│  ← JPA Entities
└─────────────────────────────────┘
```

O fluxo de uma requisição segue sempre `Resource → Service → Repository → Entity`, nunca pulando camadas. Exceções de domínio são lançadas nos serviços e capturadas por um `@ControllerAdvice` na camada de resources.

---

## Modelo de Domínio

### Diagrama de Relacionamentos

```
User ──────────────────── Order ──────────────────── OrderItem ──── Product
 1                         N  1                       N        N:1
                                │                                    │
                                │ 1:1                                │ N:N
                            Payment                             Category
                                                           (tb_product_category)
```

### Entidades

#### `User` — `tb_user`
Representa um cliente do sistema.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `Long` | Chave primária (auto-increment) |
| `name` | `String` | Nome completo |
| `email` | `String` | E-mail |
| `phone` | `String` | Telefone |
| `password` | `String` | Senha |
| `orders` | `List<Order>` | Pedidos do usuário (**não serializado**) |

**Decisão de design:** `orders` recebe `@JsonIgnore` para evitar referência circular na serialização JSON — `Order` já referencia `User` via `client`, então serializar `orders` de volta causaria um loop infinito.

---

#### `Order` — `tb_order`
Representa um pedido feito por um usuário.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `Long` | Chave primária (auto-increment) |
| `moment` | `Instant` | Data/hora do pedido em UTC |
| `orderStatus` | `Integer` | Código numérico do status |
| `client` | `User` | Usuário que fez o pedido (`client_id`) |
| `items` | `Set<OrderItem>` | Itens do pedido |
| `payment` | `Payment` | Pagamento associado (pode ser `null`) |

**Decisões de design:**
- `moment` usa `java.time.Instant` com `@JsonFormat` para serializar no padrão ISO 8601.
- `orderStatus` é armazenado como `Integer` no banco, exposto via getters/setters como o enum `OrderStatus`.
- `payment` é `@OneToOne(mappedBy = "order", cascade = CascadeType.ALL)` — o lado dono é `Payment`, que usa `@MapsId` para compartilhar a PK com o pedido.
- `getTotal()` soma os subtotais de todos os `OrderItem` e retorna o valor total do pedido.

---

#### `OrderStatus` — `enums/OrderStatus.java`
Enum que codifica o ciclo de vida de um pedido com inteiros explícitos.

| Constante | Código | Significado |
|---|---|---|
| `WAITING_PAYMENT` | 1 | Aguardando pagamento |
| `PAID` | 2 | Pago |
| `SHIPPED` | 3 | Enviado |
| `DELIVERED` | 4 | Entregue |
| `CANCELED` | 5 | Cancelado |

**Decisão de design:** usar códigos inteiros explícitos (em vez do `ordinal()` padrão do Java) garante que a ordem de declaração no enum possa mudar sem corromper dados já persistidos. O método estático `valueOf(int code)` faz o lookup reverso de forma segura.

---

#### `Payment` — `tb_payment`
Representa o pagamento de um pedido.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `Long` | Chave primária — **mesma** que `Order.id` |
| `moment` | `Instant` | Data/hora do pagamento em UTC |
| `order` | `Order` | Pedido associado (**não serializado**) |

**Decisão de design:** `@MapsId` faz com que `Payment` compartilhe a mesma PK do `Order` a que pertence — elimina a necessidade de uma coluna `order_id` separada e reforça que um pagamento só existe dentro do contexto do seu pedido. `order` recebe `@JsonIgnore` para evitar referência circular.

---

#### `OrderItem` — `tb_order_item`
Representa um item dentro de um pedido: qual produto, em qual quantidade e com qual preço foi comprado.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `OrderItemPK` | Chave primária composta (order + product) |
| `quantity` | `Integer` | Quantidade do produto |
| `price` | `Double` | Preço unitário no momento da compra |

**Métodos calculados:**
- `getSubTotal()` — retorna `price * quantity` (subtotal do item).

**Decisão de design:** `OrderItem` é a solução para o relacionamento **many-to-many com atributos extras** entre `Order` e `Product`. O preço é copiado no momento da compra para preservar o valor histórico. `getOrder()` recebe `@JsonIgnore` para evitar referência circular.

---

#### `OrderItemPK` — `pk/OrderItemPK.java`
Chave primária composta (embeddable) de `OrderItem`.

| Campo | Tipo | Coluna |
|---|---|---|
| `order` | `Order` | `order_id` |
| `product` | `Product` | `product_id` |

**Decisão de design:** anotada com `@Embeddable` e embutida em `OrderItem` via `@EmbeddedId`. `hashCode` e `equals` consideram ambos os campos, impedindo que o mesmo produto apareça duas vezes no mesmo pedido.

---

#### `Product` — `tb_product`
Representa um produto disponível para venda.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `Long` | Chave primária (auto-increment) |
| `name` | `String` | Nome do produto |
| `description` | `String` | Descrição |
| `price` | `Double` | Preço atual |
| `imgUrl` | `String` | URL da imagem |
| `categories` | `Set<Category>` | Categorias do produto |

---

#### `Category` — `tb_category`
Representa uma categoria de produtos.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `Long` | Chave primária (auto-increment) |
| `name` | `String` | Nome da categoria |
| `products` | `Set<Product>` | Produtos da categoria (**não serializado**) |

---

## Relacionamentos JPA Resumidos

| Relacionamento | Cardinalidade | Coluna de junção |
|---|---|---|
| `User` → `Order` | `@OneToMany(mappedBy = "client")` | `client_id` em `tb_order` |
| `Order` → `User` | `@ManyToOne` | `client_id` |
| `Order` → `OrderItem` | `@OneToMany(mappedBy = "id.order")` | chave composta em `tb_order_item` |
| `OrderItem` → `Order` | via `OrderItemPK` / `@ManyToOne` | `order_id` |
| `OrderItem` → `Product` | via `OrderItemPK` / `@ManyToOne` | `product_id` |
| `Product` ↔ `Category` | `@ManyToMany` | tabela `tb_product_category` |
| `Order` → `Payment` | `@OneToOne(cascade = ALL)` | PK compartilhada via `@MapsId` |

---

## Camada de Serviços

Cada serviço é anotado com `@Service` e usa **injeção de dependência via construtor**.

| Serviço | Métodos |
|---|---|
| `UserService` | `findAll()`, `findById(id)`, `insert(obj)`, `delete(id)`, `update(id, obj)` |
| `OrderService` | `findAll()`, `findById(id)` |
| `ProductService` | `findAll()`, `findById(id)` |
| `CategoryService` | `findAll()`, `findById(id)` |

`UserService` é o único com CRUD completo implementado até o momento. Os demais serviços ainda expõem apenas consultas.

---

## Endpoints REST

Todos os controllers usam `@RestController` e retornam `ResponseEntity<T>` para controle explícito do status HTTP.

### Users

| Método | Endpoint | Status de sucesso | Descrição |
|---|---|---|---|
| GET | `/users` | 200 OK | Lista todos os usuários |
| GET | `/users/{id}` | 200 OK | Busca usuário por ID |
| POST | `/users` | 201 Created | Cria novo usuário |
| PUT | `/users/{id}` | 200 OK | Atualiza nome, e-mail e telefone |
| DELETE | `/users/{id}` | 204 No Content | Remove usuário por ID |

> **POST** retorna o header `Location` com a URI do recurso criado.  
> **PUT** atualiza apenas `name`, `email` e `phone` (senha não é alterada por este endpoint).

### Orders

| Método | Endpoint | Status de sucesso | Descrição |
|---|---|---|---|
| GET | `/orders` | 200 OK | Lista todos os pedidos |
| GET | `/orders/{id}` | 200 OK | Busca pedido por ID |

### Products

| Método | Endpoint | Status de sucesso | Descrição |
|---|---|---|---|
| GET | `/products` | 200 OK | Lista todos os produtos |
| GET | `/products/{id}` | 200 OK | Busca produto por ID |

### Categories

| Método | Endpoint | Status de sucesso | Descrição |
|---|---|---|---|
| GET | `/categories` | 200 OK | Lista todas as categorias |
| GET | `/categories/{id}` | 200 OK | Busca categoria por ID |

---

## Tratamento de Exceções

O projeto implementa um mecanismo centralizado de tratamento de erros:

### Exceções de domínio (`services/exceptions/`)

| Classe | Herda de | Quando é lançada |
|---|---|---|
| `ResourceNotFoundException` | `RuntimeException` | Recurso não encontrado pelo ID informado |
| `DatabaseException` | `RuntimeException` | Violação de integridade referencial ao deletar (ex.: usuário com pedidos) |

### Handler global (`resources/exceptions/`)

`ResourceExceptionHandler` — anotado com `@ControllerAdvice`, intercepta as exceções de domínio e retorna um corpo de erro padronizado.

| Exceção capturada | Status HTTP retornado |
|---|---|
| `ResourceNotFoundException` | 404 Not Found |
| `DatabaseException` | 400 Bad Request |

### Corpo de erro — `StandardError`

```json
{
  "timestamp": "2024-06-20T19:53:07Z",
  "status": 404,
  "error": "Resource not found",
  "message": "Resource not found. Id 99",
  "path": "/users/99"
}
```

---

## Perfis e Banco de Dados

O perfil ativo é `test` (definido em `application.properties`). Com ele ativo, o `TestConfig` (implementa `CommandLineRunner`) popula o banco H2 em memória na inicialização com:

- **2 usuários:** Maria Brown, Alex Green
- **3 pedidos** com status variados (PAID, WAITING_PAYMENT)
- **1 pagamento** associado ao pedido PAID
- **3 categorias:** Electronics, Books, Computers
- **5 produtos** com associações a categorias
- **4 itens de pedido** distribuídos entre os pedidos

O schema é gerenciado pelo Hibernate (`ddl-auto=update`) — não há scripts SQL manuais.

### Perfil `prod` — PostgreSQL

Configurado em `application-prod.properties`. Em vez de valores fixos, lê três variáveis de ambiente, mantendo credenciais fora do código:

```properties
spring.datasource.url=${DB_URL}
spring.datasource.username=${DB_USER}
spring.datasource.password=${DB_PASS}
```

O perfil é selecionado pela variável de ambiente `SPRING_PROFILES_ACTIVE=prod`, que tem prioridade sobre o `spring.profiles.active=test` do `application.properties`. Assim o **mesmo JAR/imagem** roda com H2 localmente e com PostgreSQL em produção, sem recompilar. O `TestConfig` (seed) só roda no perfil `test`, então o banco `prod` começa vazio.

---

## Containerização (Docker)

O projeto é empacotado em uma imagem Docker via **multi-stage build** (`Dockerfile`):

1. **Estágio `build`** — imagem `maven:3.9-eclipse-temurin-21` compila o projeto e gera o JAR.
2. **Estágio `runtime`** — imagem `eclipse-temurin:21-jre-alpine` (mínima) recebe apenas o JAR.

O resultado é uma imagem enxuta (só JRE + JAR, sem Maven nem código-fonte). O `.dockerignore` evita copiar `target/`, `.git/` e afins para o contexto de build.

### Rodar localmente com Docker Compose

O `docker-compose.yml` sobe **app + PostgreSQL** juntos:

```powershell
# Sobe os dois containers (constrói a imagem do app na primeira vez)
docker compose up --build

# Em background
docker compose up --build -d

# Para e remove os containers (dados do volume são preservados)
docker compose down

# Para e APAGA o volume (reseta o banco)
docker compose down -v
```

Detalhes do Compose:
- O serviço `db` usa um **healthcheck** (`pg_isready`); o serviço `app` só inicia após o banco estar saudável (`depends_on: condition: service_healthy`).
- Os dados do PostgreSQL persistem em um **volume nomeado** (`postgres_data`).
- Dentro da rede do Compose, o app alcança o banco pelo hostname `db` (nome do serviço) — daí `DB_URL=jdbc:postgresql://db:5432/coursedb`.

Após subir, a API responde em `http://localhost:8080`.

---

## Deploy em Produção (Railway)

A aplicação está publicada no [Railway](https://railway.app) usando o `Dockerfile` (o `docker-compose.yml` é apenas para uso local).

### Passos

1. **New Project → Deploy from GitHub repo** — o Railway detecta o `Dockerfile` automaticamente.
2. **Add Database → PostgreSQL** — provisiona um banco gerenciado.
3. No serviço da aplicação, definir as **variáveis de ambiente** referenciando o serviço do banco:

| Variável | Valor |
|---|---|
| `SPRING_PROFILES_ACTIVE` | `prod` |
| `DB_URL` | `jdbc:postgresql://${{Postgres.RAILWAY_TCP_PROXY_DOMAIN}}:${{Postgres.RAILWAY_TCP_PROXY_PORT}}/${{Postgres.PGDATABASE}}` |
| `DB_USER` | `${{Postgres.PGUSER}}` |
| `DB_PASS` | `${{Postgres.PGPASSWORD}}` |

4. **Settings → Networking → Generate Domain** — gera a URL pública.

### Notas aprendidas no processo

- A URL do datasource **precisa** do prefixo `jdbc:` — o Railway fornece `DATABASE_URL` no formato `postgresql://...`, que o Spring/HikariCP rejeita (`'url' must start with "jdbc"`).
- Referências `${{Servico.VARIAVEL}}` ligam pelo **nome do serviço**. Renomear ou recriar o banco exige reconfigurar as referências — no canvas do Railway, a **seta** entre serviços indica uma referência ativa.
- O heap da JVM é limitado no `Dockerfile` (`-Xmx256m`) para caber no plano gratuito do Railway (0.5 GB RAM).

---

## Estrutura de Pacotes

Arquivos de infraestrutura na raiz do projeto:

```
course/
├── Dockerfile                               # Multi-stage build (Maven → JRE Alpine)
├── docker-compose.yml                       # app + PostgreSQL para rodar localmente
├── .dockerignore                            # Exclui target/, .git/ etc. do build
└── src/main/resources/
    ├── application.properties               # Config base (perfil ativo: test)
    ├── application-test.properties          # H2 em memória
    └── application-prod.properties          # PostgreSQL via variáveis de ambiente
```

```
src/main/java/com/educandoweb/course/
├── CourseApplication.java                   # Ponto de entrada Spring Boot
├── config/
│   └── TestConfig.java                      # Seed de dados (perfil test)
├── entities/
│   ├── User.java
│   ├── Order.java
│   ├── OrderItem.java
│   ├── Product.java
│   ├── Category.java
│   ├── Payment.java
│   ├── enums/
│   │   └── OrderStatus.java
│   └── pk/
│       └── OrderItemPK.java                 # Chave composta de OrderItem
├── repositories/
│   ├── UserRepository.java
│   ├── OrderRepository.java
│   ├── OrderItemRepository.java
│   ├── ProductRepository.java
│   └── CategoryRepository.java
├── services/
│   ├── UserService.java                     # CRUD completo
│   ├── OrderService.java
│   ├── ProductService.java
│   ├── CategoryService.java
│   └── exceptions/
│       ├── ResourceNotFoundException.java   # 404
│       └── DatabaseException.java           # 400
└── resources/
    ├── UserResource.java                    # CRUD completo
    ├── OrderResource.java
    ├── ProductResource.java
    ├── CategoryResource.java
    └── exceptions/
        ├── ResourceExceptionHandler.java    # @ControllerAdvice global
        └── StandardError.java              # DTO de resposta de erro
```
