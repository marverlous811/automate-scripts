# automate-scripts

## 1. Mục đích

`postgres_backup.sh` backup một cơ sở dữ liệu PostgreSQL, nén file backup bằng gzip rồi upload lên AWS S3 hoặc MinIO. Mọi cấu hình đều truyền qua biến môi trường.

Script chạy theo các bước:

1. Kiểm tra các biến bắt buộc. Thiếu biến nào thì script in lỗi và thoát với mã `1`.
2. Dùng `pg_dump` để dump database ra file SQL dạng plain text (`-F p`): `/tmp/pg_backups/<SERVICE_NAME>-<YYYYMMDD>.sql`.
3. Nén file bằng `gzip -f` thành `<SERVICE_NAME>-<YYYYMMDD>.sql.gz`.
4. Upload bằng `aws s3 cp` lên `s3://<S3_BUCKET>/[<S3_PREFIX>/]<SERVICE_NAME>-<YYYYMMDD>.sql.gz`. Nếu `USE_MINIO=true`, script thêm `--endpoint-url <MINIO_ENDPOINT>`.
5. Xóa file `.sql.gz` tạm trên máy.

Script dùng `set -e`, nên lỗi ở bất kỳ bước nào sẽ dừng script ngay.

**Công cụ cần có khi chạy:**

| Công cụ | Dùng để |
|---|---|
| `bash` | Chạy script (shebang `#!/bin/bash`) |
| `pg_dump` (gói PostgreSQL client) | Dump database |
| `gzip` | Nén file backup |
| `aws` (AWS CLI) | Upload lên S3/MinIO (`aws s3 cp`) |
| `date`, `mkdir`, `rm` | Lệnh shell cơ bản có sẵn trong hầu hết image Linux |

`Dockerfile` trong repo (base `alpine:3.21`) đã cài sẵn `bash`, `postgresql-client`, `gzip` và `awscli`. Nó cũng copy script vào `/app/postgres_backup.sh` và đặt script làm `ENTRYPOINT`.

> Lưu ý:
> - Tên file chỉ có ngày (`YYYYMMDD`). Nếu chạy nhiều lần trong một ngày với cùng `SERVICE_NAME` và `S3_PREFIX`, lần sau sẽ ghi đè object của lần trước.
> - Phiên bản `pg_dump` nên bằng hoặc mới hơn phiên bản PostgreSQL server. Nếu cũ hơn, `pg_dump` sẽ báo lỗi.

## 2. Biến môi trường

| Tên biến | Nhóm | Mô tả | Bắt buộc | Giá trị mặc định | Ví dụ |
|---|---|---|---|---|---|
| `SERVICE_NAME` | Chung | Tiền tố của tên file backup: `<SERVICE_NAME>-<YYYYMMDD>.sql.gz`. | Có | — | `my-app` |
| `PGHOST` | PostgreSQL | Host của PostgreSQL server, truyền vào `pg_dump -h`. | Có | — | `db.example.internal` |
| `PGPORT` | PostgreSQL | Port của PostgreSQL server, truyền vào `pg_dump -p`. | Không (script không kiểm tra biến này, dù có in nó trong danh sách biến bắt buộc khi báo lỗi) | `5432` | `5432` |
| `PGDATABASE` | PostgreSQL | Tên database cần backup, truyền vào `pg_dump -d`. | Có | — | `my_app_db` |
| `PGUSER` | PostgreSQL | User dùng để kết nối, truyền vào `pg_dump -U`. | Có | — | `backup_user` |
| `PGPASSWORD` | PostgreSQL | Mật khẩu của `PGUSER`. `pg_dump` đọc mật khẩu từ biến này. | Có | — | `changeme` |
| `S3_BUCKET` | Lưu trữ | Tên bucket trên S3/MinIO để upload backup. | Có | — | `my-backups` |
| `S3_PREFIX` | Lưu trữ | Thư mục (prefix) trong bucket. Có giá trị thì object nằm ở `s3://<S3_BUCKET>/<S3_PREFIX>/<file>`. Không đặt hoặc để rỗng thì object nằm ở gốc bucket: `s3://<S3_BUCKET>/<file>`. Không thêm `/` ở đầu hay cuối, vì script tự nối bằng `/`. | Không | rỗng (upload vào gốc bucket) | `postgres/my-app` |
| `AWS_ACCESS_KEY_ID` | Lưu trữ | Access key của AWS hoặc MinIO, được AWS CLI dùng. | Có | — | `EXAMPLEACCESSKEY` |
| `AWS_SECRET_ACCESS_KEY` | Lưu trữ | Secret key của AWS hoặc MinIO, được AWS CLI dùng. | Có | — | `example-secret-key` |
| `AWS_DEFAULT_REGION` | Lưu trữ | Region của AWS S3, được AWS CLI dùng. | Không | `us-east-1` (\*) | `ap-southeast-1` |
| `USE_MINIO` | MinIO | Chỉ đúng chuỗi `true` (chữ thường) mới bật chế độ MinIO, tức là thêm `--endpoint-url $MINIO_ENDPOINT` khi upload. Mọi giá trị khác (`false`, `TRUE`, `1`, rỗng, ...) đều upload lên AWS S3. | Không | `false` | `true` |
| `MINIO_ENDPOINT` | MinIO | URL của MinIO server, truyền vào `aws s3 cp --endpoint-url`. **Chỉ cần khi `USE_MINIO=true`**. Lúc đó, thiếu biến này thì script báo lỗi và thoát. | Chỉ khi `USE_MINIO=true` | — | `http://minio:9000` |

(\*) Script gán `AWS_DEFAULT_REGION=${AWS_DEFAULT_REGION:-us-east-1}` nhưng không `export`. Vì vậy, khi biến này không được truyền từ môi trường, giá trị `us-east-1` chỉ tồn tại trong script và AWS CLI không nhận được nó. Nên đặt `AWS_DEFAULT_REGION` tường minh khi dùng AWS S3.

## 3. Ví dụ chạy bằng docker compose

Ví dụ dưới đây build image từ `Dockerfile` trong repo. Image này đã có đủ công cụ ở phần Mục đích, và script đã được copy vào `/app/postgres_backup.sh` làm entrypoint, nên không cần mount script. Bí mật được đọc từ file `.env` (dạng `${...}`) hoặc từ `env_file`, không ghi thẳng vào `docker-compose.yml`.

### 3.1. `docker-compose.yml`

```yaml
services:
  # Upload lên AWS S3
  backup-s3:
    build:
      context: .
      dockerfile: Dockerfile
    env_file:
      - backup.env            # chứa PG* và AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY
    environment:
      SERVICE_NAME: my-app
      S3_BUCKET: ${S3_BUCKET}
      S3_PREFIX: postgres/my-app
      AWS_DEFAULT_REGION: ap-southeast-1
      USE_MINIO: "false"

  # Upload lên MinIO: khác backup-s3 ở USE_MINIO và MINIO_ENDPOINT
  backup-minio:
    build:
      context: .
      dockerfile: Dockerfile
    env_file:
      - backup.env
    environment:
      SERVICE_NAME: my-app
      S3_BUCKET: ${S3_BUCKET}
      S3_PREFIX: postgres/my-app
      USE_MINIO: "true"
      MINIO_ENDPOINT: ${MINIO_ENDPOINT}   # ví dụ http://minio:9000
```

### 3.2. `backup.env` (giá trị giả, không commit file thật)

```dotenv
PGHOST=db.example.internal
PGPORT=5432
PGDATABASE=my_app_db
PGUSER=backup_user
PGPASSWORD=changeme

# Với MinIO: đây là access key / secret key của MinIO
AWS_ACCESS_KEY_ID=EXAMPLEACCESSKEY
AWS_SECRET_ACCESS_KEY=example-secret-key
```

### 3.3. `.env` (docker compose tự đọc để thay `${...}`)

```dotenv
S3_BUCKET=my-backups
MINIO_ENDPOINT=http://minio:9000
```

### 3.4. Lệnh chạy

```bash
# Backup và upload lên AWS S3
docker compose run --rm backup-s3

# Backup và upload lên MinIO
docker compose run --rm backup-minio
```

Nếu chạy thành công, log kết thúc bằng `Backup process completed successfully at ...`. Object sẽ nằm tại `s3://my-backups/postgres/my-app/my-app-<YYYYMMDD>.sql.gz`.

Có thể chạy định kỳ bằng cron trên host, ví dụ backup lúc 2 giờ sáng mỗi ngày:

```cron
0 2 * * * cd /path/to/automate-scripts && docker compose run --rm backup-s3
```
