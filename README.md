# Синхронизация данных из топиков Apache Kafka® в бакет Yandex Object Storage без использования интернета

С помощью [сервисного подключения](https://yandex.cloud/ru/docs/vpc/concepts/private-endpoint) в пользовательской сети, где располагается кластер [Managed Service for Apache Kafka®](https://yandex.cloud/ru/docs/managed-kafka), вы можете синхронизировать данные из топиков Apache Kafka® в бакет [Yandex Object Storage](https://yandex.cloud/ru/docs/storage) без выхода в интернет.

Настройка через Terraform описана в [практическом руководстве](https://yandex.cloud/ru/docs/tutorials/dataplatform/kafka-topic-s3-sync-private), необходимый для настройки конфигурационный файл [kafka-objstorage-sync-private-network.tf](https://github.com/yandex-cloud-examples/yc-sync-kafka-to-s3-private-endpoint/blob/main/kafka-objstorage-sync-private-network.tf) расположен в этом репозитории.

