# TP3 - GameCloud API Serverless

## Objetivo
Implementar y desplegar una arquitectura Serverless desacoplada y altamente disponible sobre AWS (simulada localmente con MiniStack / LocalStack). El sistema expone un frontend estático para los juegos **Doom** y **Pac-Man**, procesa los puntajes de los jugadores de forma asíncrona mediante colas de mensajes (SQS) y funciones Lambda, y persiste los datos en una base NoSQL (DynamoDB).

---

## Arquitectura de la Solución
1. **Frontend Estático**: Hospedado en **Amazon S3** (`gamecloud-web`) y distribuido mediante **CloudFront**.
2. **API Gateway (HTTP API)**: Puntos de entrada para interactuar con la plataforma (`POST /scores` y `GET /ranking`).
3. **Ingesta (Lambda `recibir_puntaje`)**: Valida las peticiones de los juegos y las encola en SQS.
4. **Desacoplamiento (SQS & DLQ)**: Cola principal (`puntajes`) para amortiguar la carga y cola de mensajes fallidos (`puntajes-dlq`).
5. **Procesamiento (Lambda `procesar_puntaje`)**: Consume asíncronamente los mensajes de SQS y actualiza las puntuaciones en DynamoDB.
6. **Consulta (Lambda `ranking`)**: Lee y devuelve la lista de posiciones desde DynamoDB.
7. **Persistencia (DynamoDB)**: Tabla `Puntajes` estructurada con clave de partición `juego` (HASH) y clave de ordenamiento `jugador` (RANGE).

---

## Estructura del Proyecto

```text
tp3-gamecloud/
├── docker-compose.yml         # Configuración para levantar MiniStack/LocalStack
├── iam/
│   ├── politica-lambdas.json  # Políticas de acceso a DynamoDB, SQS y CloudWatch Logs
│   └── trust-lambda.json      # Documento AssumeRole para ejecuciones de Lambda
├── lambdas/
│   ├── procesar_puntaje.py    # Trigger de SQS que guarda en DynamoDB
│   ├── ranking.py             # Handler de GET /ranking que lee de DynamoDB
│   └── recibir_puntaje.py     # Handler de POST /scores que envía a SQS
├── scripts/
│   ├── clean.sh               # Script de eliminación y limpieza completa de recursos
│   ├── deploy.sh              # Script de despliegue automatizado de la arquitectura
│   └── test.sh                # Script de prueba de integración E2E (Doom y Pac-Man)
└── web/
    ├── config.js              # Configuración inyectada dinámicamente con la URL del API Gateway
    └── index.html             # Frontend e interfaz gráfica de los juegos
```

---

## Requisitos Previos

* **Docker** y **Docker Compose**
* **AWS CLI** instalado y configurado con credenciales de prueba.
* Alias configurado para interactuar con LocalStack/MiniStack:
  ```bash
  alias awsl="aws --endpoint-url=http://localhost:4566"
  ```
* Herramientas CLI auxiliares: `curl` y `zip`.
* *Nota:* No es necesario configurar credenciales de AWS ni el alias `awsl` en tu terminal, ya que cada script (`.sh`) incluye en su cabecera su propia configuración apuntando a `localhost:4566`.

---

## Instrucciones de Uso

### 1. Levantar la infraestructura base
Utiliza el archivo `docker-compose.yml` incluido para iniciar MiniStack en segundo plano:
```bash
docker compose up -d
```

### 2. Desplegar los servicios (Deploy)
El script automatiza la creación de S3, CloudFront, DynamoDB, SQS, roles IAM, Lambdas y API Gateway:
```bash
./scripts/deploy.sh
```

### 3. Pruebas de Integración E2E (Test)
Inyecta puntajes simulados para Doom y Pac-Man, validando el recorrido desde API Gateway hasta DynamoDB pasando por las colas SQS:
```bash
./scripts/test.sh
```

### 4. Limpiar el entorno (Clean)
Elimina ordenadamente todos los recursos creados en AWS local dejándolo en blanco sin apagar el contenedor Docker:
```bash
./scripts/clean.sh
```

---

## Endpoints de la API

| Método | Ruta | Descripción | Ejemplo de Entrada |
| :--- | :--- | :--- | :--- |
| `POST` | `/scores` | Registra el puntaje de un jugador en la cola SQS | `{"juego": "doom", "jugador": "Slayer99", "puntaje": 9500}` |
| `GET` | `/ranking` | Retorna las puntuaciones registradas por juego | Query Param: `?juego=doom` o `?juego=pacman` |

