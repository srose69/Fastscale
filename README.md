# Fastscale: Your Headscale VPN Server in Minutes.

[English](#english) | [Русский](#русский)

A fully automated, interactive setup script for a self-hosted Headscale (Tailscale control server) instance. Get your own private, secure, and modern VPN up and running in minutes, without hunting through dozens of manuals.

---
<a name="english"></a>

## Features

* **Interactive Guided Setup**: The script asks you simple questions and handles all the complex configuration for you.
* **Headscale**: Deploys the latest version of the powerful open-source Tailscale control server.
* **Web UI Included**: Comes with the popular `headscale-admin` UI out-of-the-box for easy management of users, nodes, and routes.
* **Dockerized**: All services run in isolated Docker containers for clean and easy management.
* **Nginx Reverse Proxy**: Automatically configures Nginx to handle traffic and route it to the appropriate services.
* **Automatic SSL**: Provisions and configures free, trusted SSL certificates from Let's Encrypt (`certbot`).
* **OIDC Post-Install Helper**: Includes a separate interactive script (`oidc.sh`) to easily configure OIDC authentication (e.g., "Sign in with Google") after the initial setup.
* **Optional Nginx UI**: An option to also install `nginx-ui` for graphical management of Nginx configs.

## What Problem Does This Solve?

Setting up a self-hosted VPN with all the modern features (like a control server, UI, OIDC, and SSL) is a complex task. It usually requires deep knowledge of Docker, Nginx, Linux networking, and reading multiple, often conflicting, guides.

**Fastscale solves this.** It's a single, robust script that automates the entire process from start to finish. You provide your domain, and the script takes care of the rest, creating a production-ready, secure VPN server.

## Prerequisites

* A Linux server (Ubuntu 22.04+ recommended) with a public IP address.
* A domain name (e.g., `vpn.yourcompany.com`) pointed to your server's public IP.
* `sudo` (root) access on the server.

## Quick Start

1.  Clone this repository onto your server:
    ```bash
    git clone [https://github.com/your-username/Fastscale.git](https://github.com/your-username/Fastscale.git)
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
    The script will ask you for your domain, email, and which optional components you want to install. Just follow the prompts.

## Post-Installation: Final Steps

After the main script finishes, your Headscale server will be running.

1.  **Get Your Admin API Key**: The script will create a file named `API_DELETEME_your.domain.com.KEY`. This key is used to log in to the `headscale-admin` UI. View it with `sudo cat API_DELETEME_...KEY`.
2.  **Log in to the UI**: Go to `https://your.domain.com/admin/`, click the settings icon (⚙️), and enter the API key.
3.  **(Optional) Configure OIDC**: To enable login via Google or another OIDC provider, run the post-installation script:
    ```bash
    sudo ./oidc.sh
    ```
    This helper script will ask you for your OIDC provider's details (Client ID, Secret, etc.) and automatically update the Headscale configuration.

---
<a name="русский"></a>

# Fastscale: Ваш VPN-сервер Headscale за 5 минут.

[English](#english) | [Русский](#русский)

Полностью автоматизированный интерактивный скрипт для развертывания вашего собственного VPN-сервера на базе Headscale (open-source аналог Tailscale). Запустите свою приватную, безопасную и современную VPN-сеть за считанные минуты, не изучая десятки мануалов.

---

## Возможности

* **Интерактивная установка**: Скрипт задает простые вопросы и сам справляется со всей сложной настройкой.
* **Headscale**: Разворачивает последнюю версию мощного open-source сервера управления Tailscale.
* **Веб-интерфейс в комплекте**: Поставляется с популярным UI `headscale-admin` для удобного управления пользователями, устройствами и маршрутами.
* **Все в Docker**: Сервисы работают в изолированных Docker-контейнерах, что обеспечивает чистоту системы и простоту управления.
* **Nginx Reverse Proxy**: Автоматически настраивает Nginx для обработки трафика и маршрутизации к нужным сервисам.
* **Автоматический SSL**: Получает и настраивает бесплатные, доверенные SSL-сертификаты от Let's Encrypt (`certbot`).
* **Помощник настройки OIDC**: Включает отдельный интерактивный скрипт (`oidc_ru.sh`) для легкой настройки входа через OIDC (например, "Войти через Google") после основной установки.
* **Опциональный Nginx UI**: Возможность дополнительно установить `nginx-ui` для графического управления конфигурациями Nginx.

## Какую проблему решает?

Настройка собственного VPN-сервера со всеми современными функциями (сервер управления, UI, OIDC, SSL) — сложная задача. Она требует глубоких знаний Docker, Nginx, сетевых настроек Linux и изучения множества, часто противоречащих друг другу, руководств.

**Fastscale решает эту проблему.** Это единый, надежный скрипт, который автоматизирует весь процесс от начала до конца. Вы указываете свой домен, а скрипт берет на себя все остальное, создавая готовый к работе и безопасный VPN-сервер.

## Требования

* Linux-сервер (рекомендуется Ubuntu 22.04+) с публичным IP-адресом.
* Доменное имя (например, `vpn.yourcompany.com`), направленное на публичный IP вашего сервера.
* `sudo` (root) доступ на сервере.

## Быстрый старт

1.  Склонируйте репозиторий на ваш сервер:
    ```bash
    git clone [https://github.com/your-username/Fastscale.git](https://github.com/your-username/Fastscale.git)
    cd Fastscale
    ```

2.  Сделайте скрипты исполняемыми:
    ```bash
    chmod +x setup_ru.sh oidc_ru.sh
    ```

3.  Запустите основной скрипт установки:
    ```bash
    sudo ./setup_ru.sh
    ```
    Скрипт спросит ваш домен, email и какие опциональные компоненты вы хотите установить. Просто следуйте инструкциям.

## Пост-установка: Финальные шаги

После завершения основного скрипта ваш сервер Headscale будет запущен.

1.  **Получите API ключ администратора**: Скрипт создаст файл `API_DELETEME_your.domain.com.KEY`. Этот ключ используется для входа в UI `headscale-admin`. Посмотрите его командой `sudo cat API_DELETEME_...KEY`.
2.  **Войдите в UI**: Перейдите по адресу `https://your.domain.com/admin/`, нажмите на кнопку настроек и введите API ключ.
3.  **(Опционально) Настройте OIDC**: Чтобы включить вход через Google или другого OIDC-провайдера, запустите скрипт пост-настройки:
    ```bash
    sudo ./oidc_ru.sh
    ```
    Этот скрипт-помощник запросит данные вашего OIDC-провайдера (Client ID, Secret и т.д.) и автоматически обновит конфигурацию Headscale.
