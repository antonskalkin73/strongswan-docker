# strongswan-docker

[English](README.md) | [Русский](README.ru.md)

Готовый к продакшену Docker-образ для запуска **IKEv2 VPN-сервера на strongSwan**,
публикуемый в GitHub Container Registry (GHCR) и разворачиваемый на Linux VPS с
Docker Compose v2.

---

## Содержание

1. [Назначение проекта](#1-назначение-проекта)
2. [Обзор архитектуры](#2-обзор-архитектуры)
3. [Модель безопасности](#3-модель-безопасности)
4. [Структура репозитория](#4-структура-репозитория)
5. [Локальная сборка](#5-локальная-сборка)
6. [Публикация в GHCR](#6-публикация-в-ghcr)
7. [Развертывание на VPS](#7-развертывание-на-vps)
8. [Обновление контейнера](#8-обновление-контейнера)
9. [Файлы: примеры и секреты](#9-файлы-примеры-и-секреты)
10. [Устранение неполадок](#10-устранение-неполадок)

---

## 1. Назначение проекта

Этот проект упаковывает [strongSwan](https://www.strongswan.org/) — широко
используемую open-source реализацию IPsec/IKEv2 VPN — в минимальный Docker-образ
на базе Ubuntu.  
Образ **универсальный и не содержит секретов**; вся конфигурация времени
выполнения, сертификаты и учетные данные монтируются с хоста при старте
контейнера.

Типовой сценарий использования: roadwarrior IKEv2 VPN на недорогом Linux VPS,
который дает удаленным клиентам зашифрованный доступ в интернет или в частную
подсеть.

---

## 2. Обзор архитектуры

```
GitHub repo (source + CI)
        │
        │  push / tag
        ▼
GitHub Actions workflow
        │
        │  docker build + push
        ▼
GHCR  ghcr.io/antonskalkin73/strongswan-docker:latest
        │
        │  docker compose pull
        ▼
VPS (Ubuntu + Docker Engine)
  ┌─────────────────────────────────┐
  │  контейнер strongSwan           │
  │  network_mode: host             │
  │                                 │
  │  /etc/ipsec.conf       ◄── ro mount from ./config/
  │  /etc/strongswan.conf  ◄── ro mount from ./config/
  │  /etc/ipsec.secrets    ◄── ro mount from ./config/
  │  /etc/ipsec.d/         ◄── ro mount from ./certs/
  └─────────────────────────────────┘
```

Контейнер использует **host networking**, чтобы strongSwan имел прямой доступ к
физическому сетевому интерфейсу и UDP-портам 500/4500 без лишней сложности с
маппингом портов.

---

## 3. Модель безопасности

| Вопрос | Подход |
|---|---|
| Секреты в образе | Отсутствуют. Сертификаты и PSK монтируются во время запуска. |
| Секреты в репозитории | `.gitignore` исключает `.env`, `config/ipsec.secrets` и всё в `certs/` (кроме `.gitkeep`). |
| Монтирование с минимальными правами | Все тома с конфигами и сертификатами монтируются **только для чтения** (`:ro`). |
| Возможности ядра | Добавлены только `NET_ADMIN` и `SYS_MODULE`. |
| Базовый образ | Ubuntu 24.04 LTS — регулярно получает обновления upstream. |
| Токен CI | Вход в GHCR в CI использует автоматически созданный `GITHUB_TOKEN`; персональные токены не хранятся. |

> **Правило:** если файл содержит пароль, приватный ключ или PSK, его нельзя
> коммитить. Используйте файлы `*.example` только как шаблоны.

---

## 4. Структура репозитория

```
strongswan-docker/
├── .github/
│   └── workflows/
│       └── docker-publish.yml   # CI: build & push to GHCR
├── config/
│   ├── ipsec.conf               # Пример конфигурации IKEv2 roadwarrior
│   ├── strongswan.conf          # Конфиг демона Charon
│   └── ipsec.secrets.example    # Шаблон: скопируйте и заполните на VPS
├── certs/
│   └── .gitkeep                 # Сохраняет каталог в git; реальные сертификаты лежат здесь
├── Dockerfile
├── entrypoint.sh
├── compose.yaml
├── .env.example                 # Скопируйте в .env на VPS и заполните
├── .gitignore
├── README.md
└── README.ru.md                 # Русская версия этой инструкции
```

---

## 5. Локальная сборка

```bash
# Клонируйте репозиторий
git clone https://github.com/antonskalkin73/strongswan-docker.git
cd strongswan-docker

# Соберите образ локально
docker build -t strongswan-local .

# Проверьте метаданные образа
docker image inspect strongswan-local
```

Для локального тестирования всё равно нужны runtime-конфиги (см.
[Развертывание на VPS](#7-развертывание-на-vps)).

---

## 6. Публикация в GHCR

Образы публикуются автоматически workflow GitHub Actions
(`.github/workflows/docker-publish.yml`):

| Событие | Тег образа |
|---|---|
| Push в `main` | `latest`, `<версия-strongSwan>` |
| Push тега `v1.2.3` | `1.2.3`, `1.2`, `latest`, `<версия-strongSwan>` |
| Pull request | Только сборка, без push |

Дополнительно каждый опубликованный образ получает тег, совпадающий с версией
strongSwan, установленной внутри контейнера, например `5.9.13`.

Workflow использует `secrets.GITHUB_TOKEN` — дополнительные секреты или PAT не
нужны.  
Чтобы настроить пакет, откройте:  
**GitHub → ваш профиль → Packages → strongswan-docker → Package settings →
Change visibility** (сделайте пакет Public или оставьте Private, если нужно).

Если видимость пакета установлена в **Public**, образ можно скачать без
авторизации:

```bash
docker pull ghcr.io/antonskalkin73/strongswan-docker:latest
```

---

## 7. Развертывание на VPS

### 7.1 Предварительные требования

- Ubuntu 22.04 / 24.04 VPS с публичным IP-адресом
- Установленный Docker Engine: <https://docs.docker.com/engine/install/ubuntu/>
- Плагин Docker Compose v2: входит в Docker Engine ≥ 20.10 (`docker compose`)

### 7.2 Создайте структуру runtime-каталогов

```bash
git clone https://github.com/antonskalkin73/strongswan-docker.git
cd strongswan-docker

# Скопируйте примерные файлы и заполните их
cp .env.example .env
nano .env                              # укажите VPN_FQDN

cp config/ipsec.secrets.example config/ipsec.secrets
nano config/ipsec.secrets             # укажите реальные учетные данные
chmod 600 config/ipsec.secrets        # ограничьте права доступа

# При необходимости отредактируйте конфиги
nano config/ipsec.conf
nano config/strongswan.conf
```

### 7.3 Сгенерируйте и разместите сертификаты

Инструмент `pki` из strongSwan может создать самоподписанный CA и серверный
сертификат. Сертификаты должны лежать в подкаталогах `certs/`, которые ожидает
strongSwan:

```bash
mkdir -p certs/cacerts certs/certs certs/private

# 1. Сгенерируйте приватный ключ CA и самоподписанный сертификат
docker run --rm -v "$(pwd)/certs:/out" \
  ghcr.io/antonskalkin73/strongswan-docker:latest \
  sh -c '
    ipsec pki --gen --type rsa --size 4096 --outform pem > /out/private/ca-key.pem
    ipsec pki --self --ca --lifetime 3650 \
      --in /out/private/ca-key.pem --type rsa \
      --dn "CN=VPN CA" --outform pem > /out/cacerts/ca-cert.pem
  '

# 2. Сгенерируйте приватный ключ сервера и сертификат, подписанный CA.
#    Укажите FQDN, который вы записали в .env (VPN_FQDN=...).
FQDN=vpn.example.com   # <-- замените на ваш реальный FQDN

docker run --rm -v "$(pwd)/certs:/out" \
  -e FQDN="$FQDN" \
  ghcr.io/antonskalkin73/strongswan-docker:latest \
  sh -c '
    ipsec pki --gen --type rsa --size 4096 --outform pem > /out/private/server-key.pem
    ipsec pki --pub --in /out/private/server-key.pem --type rsa |
      ipsec pki --issue --lifetime 1825 \
        --cacert /out/cacerts/ca-cert.pem \
        --cakey  /out/private/ca-key.pem \
        --dn "CN=$FQDN" --san "$FQDN" \
        --flag serverAuth --flag ikeIntermediate \
        --outform pem > /out/certs/server-cert.pem
  '

chmod 600 certs/private/ca-key.pem certs/private/server-key.pem
```

> Каталог `certs/` исключен из git через `.gitignore`.  
> **Надежно храните резервную копию `certs/private/` — потеря ключа CA означает,
> что придется перевыпустить все клиентские сертификаты.**

### 7.4 Запуск контейнера

```bash
docker compose pull
docker compose up -d
docker compose logs -f
```

---

## 8. Обновление контейнера

Когда в GHCR публикуется новый образ:

```bash
docker compose pull
docker compose up -d
```

Это выполняет замену контейнера без простоя.

---

## 9. Файлы: примеры и секреты

| Файл | Статус | Примечание |
|---|---|---|
| `config/ipsec.conf` | ✅ Можно коммитить | Пример конфига, без секретов |
| `config/strongswan.conf` | ✅ Можно коммитить | Конфиг демона, без секретов |
| `config/ipsec.secrets.example` | ✅ Можно коммитить | Только заглушки |
| `.env.example` | ✅ Можно коммитить | Только заглушки |
| `config/ipsec.secrets` | 🔴 **Никогда не коммитьте** | Содержит реальные пароли |
| `.env` | 🔴 **Никогда не коммитьте** | Может содержать чувствительные значения |
| `certs/*` (кроме `.gitkeep`) | 🔴 **Никогда не коммитьте** | Приватные ключи и сертификаты |

---

## 10. Устранение неполадок

### `charon` не стартует / ошибки конфигурации

Проверьте логи:

```bash
docker compose logs -f
```

### Нет входящих IKE-пакетов

Убедитесь, что:

- VPS имеет публичный IP
- UDP 500 и UDP 4500 не блокируются
- контейнер запущен в `network_mode: host`

### Клиент подключается, но трафик не проходит

Проверьте:

- правила IP forwarding / NAT на хосте
- настройки `leftsubnet` / `rightsourceip` в `config/ipsec.conf`
- firewall хоста

---

## Лицензия / замечания

Этот репозиторий содержит инфраструктуру контейнера и примеры конфигурации.
Лицензирование самого strongSwan определяется его исходным проектом и пакетами
Ubuntu.
