# Web Services com Spring Boot, JPA e Hibernate

Projeto de estudo desenvolvido no curso **Java COMPLETO** de Nelio Alves. Implementa um web service RESTful de e-commerce usando Spring Boot 3.5.10, JPA/Hibernate para ORM e H2 como banco de dados em memória.

---

## Tecnologias

| Tecnologia | Versão |
|---|---|
| Java | 21 |
| Spring Boot | 3.5.10 |
| Spring Data JPA / Hibernate | (via Spring Boot) |
| H2 Database | (via Spring Boot) |
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
│   services/   (Regras de negócio)│  ← Lógica da aplicação
├─────────────────────────────────┤
│   repositories/ (Acesso a dados) │  ← Spring Data JPA
├─────────────────────────────────┤
│   entities/   (Modelo de domínio)│  ← JPA Entities
└─────────────────────────────────┘
```

O fluxo de uma requisição segue sempre `Resource → Service → Repository → Entity`, nunca pulando camadas.

---

## Modelo de Domínio

### Diagrama de Relacionamentos

```
User ──────────────────── Order ──────────────────── OrderItem ──── Product
 1                         N  1                       N        N:1
 │                               │                    │         │
 │  (cliente faz pedidos)        │  (itens do pedido) │         │
                                 │                              │
                         OrderStatus                        Category
                         (enum)                            (N:N via
                                                       tb_product_category)
```

### Entidades

#### `User` — `tb_user`
Representa um cliente do sistema.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `Long` | Chave primária (auto-increment) |
| `name` | `String` | Nome completo (max 100) |
| `email` | `String` | E-mail (max 100) |
| `phone` | `String` | Telefone (max 50) |
| `password` | `String` | Senha (max 100) |
| `orders` | `List<Order>` | Pedidos do usuário (**não serializado**) |

**Decisão de design:** `orders` recebe `@JsonIgnore` para evitar referência circular na serialização JSON — Order já referencia User via `client`, então serializar `orders` de volta causaria um loop infinito.

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

**Decisões de design:**
- `moment` usa `java.time.Instant` (representação UTC) com `@JsonFormat` para serializar no padrão ISO 8601: `"2019-06-20T19:53:07Z"`.
- `orderStatus` é armazenado como `Integer` no banco, mas exposto como o enum `OrderStatus` via getters/setters — decisão que permite adicionar novos status sem quebrar dados existentes e torna a serialização JSON legível (retorna o nome do enum, não o inteiro).
- `items` usa `Set` em vez de `List` porque `OrderItem` tem chave composta, e `Set` evita duplicatas naturalmente via `hashCode/equals`.

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

#### `OrderItem` — `tb_order_item`
Representa um item dentro de um pedido: qual produto, em qual quantidade e com qual preço foi comprado.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `OrderItemPK` | Chave primária composta (order + product) |
| `quantity` | `Integer` | Quantidade do produto |
| `price` | `Double` | Preço unitário no momento da compra |

**Decisão de design:** `OrderItem` é a solução para o relacionamento **many-to-many com atributos extras** entre `Order` e `Product`. Uma simples `@JoinTable` não comporta `quantity` e `price`, então `OrderItem` vira uma entidade de associação com chave composta. O preço é copiado no momento da compra para preservar o valor histórico, mesmo que o preço do produto mude depois.

`getOrder()` recebe `@JsonIgnore` para evitar referência circular, já que `Order` já inclui seus `items`.

---

#### `OrderItemPK` — `pk/OrderItemPK.java`
Chave primária composta (embeddable) de `OrderItem`.

| Campo | Tipo | Coluna |
|---|---|---|
| `order` | `Order` | `order_id` |
| `product` | `Product` | `product_id` |

**Decisão de design:** anotada com `@Embeddable`, é embutida em `OrderItem` via `@EmbeddedId`. `hashCode` e `equals` consideram **ambos** os campos, garantindo unicidade da combinação pedido + produto. Isso impede que o mesmo produto apareça duas vezes no mesmo pedido.

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

**Decisão de design:** o relacionamento com `Category` é `@ManyToMany` — um produto pode pertencer a várias categorias e uma categoria pode ter vários produtos. A tabela de junção `tb_product_category` é declarada com `@JoinTable` no lado **dono** da relação (`Product`).

---

#### `Category` — `tb_category`
Representa uma categoria de produtos.

| Campo | Tipo | Descrição |
|---|---|---|
| `id` | `Long` | Chave primária (auto-increment) |
| `name` | `String` | Nome da categoria |
| `products` | `Set<Product>` | Produtos da categoria (**não serializado**) |

**Decisão de design:** `products` usa `mappedBy = "categories"` (lado inverso do many-to-many) e `@JsonIgnore` para evitar referência circular — serializar uma categoria já inclui o nome, não há necessidade de listar todos os produtos dentro dela.

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

---

## Camada de Serviços

Cada serviço é anotado com `@Service` e usa **injeção de dependência via construtor** (sem `@Autowired` no campo — prática recomendada para testabilidade).

| Serviço | Métodos |
|---|---|
| `UserService` | `findAll()`, `findById(id)` |
| `OrderService` | `findAll()`, `findById(id)` |
| `ProductService` | `findAll()`, `findById(id)` |
| `CategoryService` | `findAll()`, `findById(id)` |

---

## Endpoints REST

Todos os controllers usam `@RestController` e retornam `ResponseEntity<T>` para controle explícito do status HTTP.

| Método | Endpoint | Descrição |
|---|---|---|
| GET | `/users` | Lista todos os usuários |
| GET | `/users/{id}` | Busca usuário por ID |
| GET | `/orders` | Lista todos os pedidos |
| GET | `/orders/{id}` | Busca pedido por ID |
| GET | `/products` | Lista todos os produtos |
| GET | `/products/{id}` | Busca produto por ID |
| GET | `/categories` | Lista todas as categorias |
| GET | `/categories/{id}` | Busca categoria por ID |

---

## Perfis e Banco de Dados

O perfil ativo é `test` (definido em `application.properties`). Com ele ativo, o `TestConfig` (implementa `CommandLineRunner`) popula o banco H2 em memória na inicialização com:

- **2 usuários:** Maria Brown, Alex Green
- **3 pedidos** com status variados (PAID, WAITING_PAYMENT)
- **3 categorias:** Electronics, Books, Computers
- **5 produtos** com associações a categorias
- **4 itens de pedido** distribuídos entre os pedidos

O schema é gerenciado pelo Hibernate (`ddl-auto=update`) — não há scripts SQL manuais.

---

## Estrutura de Pacotes

```
src/main/java/com/educandoweb/course/
├── CourseApplication.java          # Ponto de entrada Spring Boot
├── config/
│   └── TestConfig.java             # Seed de dados (perfil test)
├── entities/
│   ├── User.java
│   ├── Order.java
│   ├── OrderItem.java
│   ├── Product.java
│   ├── Category.java
│   ├── enums/
│   │   └── OrderStatus.java
│   └── pk/
│       └── OrderItemPK.java        # Chave composta de OrderItem
├── repositories/
│   ├── UserRepository.java
│   ├── OrderRepository.java
│   ├── OrderItemRepository.java
│   ├── ProductRepository.java
│   └── CategoryRepository.java
├── services/
│   ├── UserService.java
│   ├── OrderService.java
│   ├── ProductService.java
│   └── CategoryService.java
└── resources/
    ├── UserResource.java
    ├── OrderResource.java
    ├── ProductResource.java
    └── CategoryResource.java
```
