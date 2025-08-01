# Fastscale: Ваш VPN-сервер Headscale "под ключ" за 5 минут.

[English](#english) | [Русский](#русский)

Интеллектуальный скрипт-установщик, который проведет вас через весь процесс развертывания Headscale — от установки зависимостей до готового к работе VPN с веб-интерфейсом и SSL.

---
<a name="russian"></a>
<a name="русский"></a>

## Возможности

* **Полная автоматизация "под ключ"**: Скрипт не просто запускает контейнеры. Он устанавливает зависимости (Docker, Nginx, Certbot), проверяет и решает конфликты портов, генерирует все конфигурации и настраивает SSL.
* **Интерактивный мастер настройки**: Забудьте о правке YAML-файлов. Скрипт в диалоговом режиме запрашивает только необходимую информацию (домен, email) и предлагает выбор компонентов.
* **Безопасность по умолчанию**: Все сервисы (Headscale, UI) работают на `127.0.0.1` и доступны извне только через Nginx reverse proxy с обязательным SSL-шифрованием от Let's Encrypt.
* **Готовая архитектура**:
    * **Headscale**: Ядро системы, последняя версия.
    * **headscale-admin (Опционально)**: Удобный веб-интерфейс для управления пользователями и устройствами, доступен по адресу `/admin`.
    * **Nginx Reverse Proxy**: Автоматически настроенный Nginx для маршрутизации трафика и терминирования SSL.
    * **Certbot**: Автоматическое получение и настройка бесплатных SSL-сертификатов.
    * **tailscale-client**: Контейнер, который сразу подключает сам сервер к вашей новой VPN-сети.
    * **nginx-ui (Опционально)**: Графический интерфейс для управления Nginx, доступен по адресу `/nginx-ui`.
* **Удобство после установки**:
    * Скрипт создает временный файл с API-ключом для первого входа в UI.
    * Генерируется файл `headscale_credentials.txt` с итоговой инструкцией и ссылками.
    * Отдельный скрипт `oidc_ru.sh` для легкой настройки входа через Google, GitHub и других OIDC-провайдеров уже после установки.
* **Продуманная работа с системой**:
    * Аккуратно работает с существующей установкой Nginx.
    * Все файлы проекта изолированы в одной директории (`htscale`).
    * Ведется подробный лог установки (`install_*.log`).

## Какую проблему решает?

Развертывание Headscale — это не просто `docker run`. Это сложный процесс, требующий:
1.  Настроить Docker и Docker Compose.
2.  Написать корректный `config.yaml` для Headscale.
3.  Установить и настроить Nginx в качестве reverse proxy.
4.  Правильно настроить SSL-сертификаты через Certbot.
5.  Связать все это вместе, открыв нужные порты и обеспечив безопасность.

**Fastscale автоматизирует все эти шаги.** Он заменяет десятки команд и часы чтения документации одним запуском скрипта. Вы отвечаете на несколько простых вопросов и получаете полностью готовый, безопасный и современный VPN-сервер.

## Требования

* Linux-сервер (рекомендуется Ubuntu 22.04+) с публичным IP-адресом.
* Доменное имя (например, `vpn.yourcompany.com`), направленное на публичный IP вашего сервера.
* `sudo` (root) доступ на сервере.

## Быстрый старт

1.  Склонируйте репозиторий на ваш сервер:
    ```bash
    git clone https://github.com/srose69/Fastscale
    cd Fastscale
    ```

2.  Сделайте скрипты исполняемыми:
    ```bash
    chmod +x setup.sh oidc_ru.sh
    ```

3.  Запустите основной скрипт установки:
    ```bash
    sudo ./setup.sh
    ```
    Скрипт спросит ваш домен, email и какие опциональные компоненты вы хотите установить. Просто следуйте инструкциям.

## Пост-установка: Финальные шаги

После завершения скрипта `setup.sh` вся информация для начала работы будет сохранена в файле `headscale_credentials.txt`.

1.  **Посмотрите инструкцию**: `sudo cat headscale_credentials.txt`. Там будут все ссылки и шаги.
2.  **Получите API-ключ**: Для первого входа в веб-интерфейс вам понадобится временный ключ. Он находится в файле `htscale/API_DELETEME.KEY`. Посмотрите его командой:
    ```bash
    sudo cat htscale/API_DELETEME.KEY
    ```
3.  **Войдите в UI**: Перейдите по адресу `https://ваш.домен/admin/`, нажмите на иконку настроек (⚙️) и вставьте скопированный ключ.
4.  **ВАЖНО! Удалите ключ**: После успешного входа обязательно удалите файл с ключом, чтобы он не оставался на сервере:
    ```bash
    sudo rm htscale/API_DELETEME.KEY
    ```
5.  **(Опционально) Настройте OIDC**: Чтобы включить вход через внешнего провайдера (Google, и т.д.), запустите второй скрипт и следуйте его инструкциям:
    ```bash
    sudo ./oidc_ru.sh
    ```

---
<a name="english"></a>

# Fastscale: Your Turnkey Headscale VPN Server in Minutes.

[English](#english) | [Русский](#русский)

An intelligent setup script that guides you through the entire Headscale deployment process—from installing dependencies to a production-ready VPN with a web UI and SSL.

---

## Features

* **Turnkey Automation**: This isn't just a container launcher. The script installs dependencies (Docker, Nginx, Certbot), checks and resolves port conflicts, generates all configurations, and provisions SSL.
* **Interactive Setup Wizard**: Forget editing YAML files. The script asks for essential information (your domain, email) in a simple Q&A format and lets you choose optional components.
* **Secure by Default**: All services (Headscale, UI) listen on `127.0.0.1` and are exposed externally only through an Nginx reverse proxy with mandatory SSL encryption from Let's Encrypt.
* **Complete Architecture**:
    * **Headscale**: The latest version of the core control server.
    * **headscale-admin (Optional)**: A user-friendly web UI for managing users and nodes, available at `/admin`.
    * **Nginx Reverse Proxy**: Automatically configured to route traffic and terminate SSL.
    * **Certbot**: For automatic fetching and renewal of free SSL certificates.
    * **tailscale-client**: A container that immediately connects the host server to your new VPN network.
    * **nginx-ui (Optional)**: A graphical interface for managing Nginx, available at `/nginx-ui`.
* **Post-Install Convenience**:
    * The script creates a temporary API key file for your first login to the web UI.
    * It generates a `headscale_credentials.txt` file with final instructions and links.
    * Includes a separate `oidc.sh` script to easily configure login via Google, GitHub, or other OIDC providers after the main setup.
* **Smart System Integration**:
    * Gracefully handles existing Nginx installations.
    * All project files are isolated in a single directory (`htscale`).
    * Maintains a detailed installation log (`install_*.log`).

## What Problem Does This Solve?

Deploying Headscale isn't just `docker run`. It's a complex process that requires you to:
1.  Set up Docker and Docker Compose correctly.
2.  Write a valid `config.yaml` for Headscale.
3.  Install and configure Nginx as a reverse proxy.
4.  Correctly set up SSL certificates via Certbot.
5.  Tie it all together, open the right ports, and ensure it's secure.

**Fastscale automates all of this.** It replaces dozens of commands and hours of reading documentation with a single script execution. You answer a few simple questions and get a fully-featured, secure, and modern VPN server.

## Prerequisites

* A Linux server (Ubuntu 22.04+ recommended) with a public IP address.
* A domain name (e.g., `vpn.yourcompany.com`) pointed to your server's public IP.
* `sudo` (root) access on the server.

## Quick Start

1.  Clone this repository onto your server:
    ```bash
    git clone https://github.com/srose69/Fastscale
    cd Fastscale
    ```

2.  Make the scripts executable:
    ```bash
    chmod +x setup.sh oidc.sh
    ```

3.  Run the main setup script:
    ```bash
    sudo ./setup.sh
    ```
    The script will ask for your domain, email, and which optional components you wish to install. Just follow the prompts.

## Post-Installation: Final Steps

After the `setup.sh` script finishes, all the information you need to get started is saved in the `headscale_credentials.txt` file.

1.  **Read the Instructions**: `sudo cat headscale_credentials.txt`. It contains all your links and next steps.
2.  **Get the API Key**: For your first login to the web UI, you'll need a temporary key located in `htscale/API_DELETEME.KEY`. View it with:
    ```bash
    sudo cat htscale/API_DELETEME.KEY
    ```
3.  **Log in to the UI**: Navigate to `https://your.domain.com/admin/`, click the settings icon (⚙️), and paste the API key.
4.  **IMPORTANT! Delete the Key**: After logging in successfully, you must delete the key file so it doesn't remain on the server:
    ```bash
    sudo rm htscale/API_DELETEME.KEY
    ```
5.  **(Optional) Configure OIDC**: To enable login via an external provider (like Google), run the second script and follow its prompts:
    ```bash
    sudo ./oidc.sh
    ```
