
# Infrastructure for the Yandex Cloud Managed Service for Apache Kafka® cluster, Virtual Machine, network, Object Storage bucket, and service account
#
# RU: https://yandex.cloud/ru/docs/tutorials/dataplatform/kafka-topic-s3-sync-private
# EN: https://yandex.cloud/en/docs/tutorials/dataplatform/kafka-topic-s3-sync-private
#
# Configure the parameters of the Managed Service for Apache Kafka® cluster, Virtual Machine, network, Object Storage bucket, and service account:
locals {
  # The following settings are to be specified by the user. Change them as you wish.

  tf_account_name = "" # Name of the service account used by Terraform to create resources

  # Settings for the Object Storage bucket:
  bucket_name = "" # Name of the Object Storage bucket

  # Settings for the Managed Service for Apache Kafka® cluster:
  mkf_version       = "" # Version of the Managed Service for Apache Kafka® cluster
  mkf_user_password = "" # Password of the Managed Service for Apache Kafka® user

  # Settings for the Virtual Machine:
  vm_image_id = "" # Public image ID from https://yandex.cloud/en/docs/compute/operations/images-with-pre-installed-software/get-list
  vm_username = "" # Name of the VM's user
  vm_ssh_key  = "" # Path to public SSH key

  # The following settings are predefined. Change them only if necessary.

  # Settings for the subnet:
  subnet_name           = "mkf-subnet-a"  # Subnet name
  subnet_zone           = "ru-central1-a" # Subnet zone
  zone_a_v4_cidr_blocks = "10.1.0.0/16"   # CIDR block for the subnet

  # Settings for the security group:
  sg_name           = "mkf-security-group" # Security group name
  allowed_port1     = "9091"               # Allowed port for incoming traffic
  allowed_port2     = "443"                # Allowed port for incoming secure traffic
  allowed_port_ssh  = "22"                 # Allowed port for traffic to VM
  port1_description = "Kafka port"         # Allowed port description

  # Settings for the Service Account:
  s3_sa_name = "storage-pe-admin" # Name of the service account

  # Settings for the Managed Service for Apache Kafka® cluster:
  mkf_environment         = "PRODUCTION"                   # Environment of the Managed Service for Apache Kafka® cluster
  mkf_cluster_description = "Managed Apache Kafka cluster" # Description of the Managed Service for Apache Kafka® cluster
  mkf_cluster_name        = "mkf-cluster"                  # Name of the Managed Service for Apache Kafka® cluster
  mkf_username            = "mkf-user"                     # Name of the Managed Service for Apache Kafka® user
  mkf_topic_name          = "my-private-topic"             # Name of the Apache Kafka® topic

  # Settings for the Virtual Machine:
  vm_name        = "vm-sync-test" # Virtual machine name
  vm_platform_id = "standard-v2"  # Virtual machine platform: Intel Cascade Lake
}

data "yandex_iam_service_account" "tf-account" {
  name = local.tf_account_name
}

resource "yandex_vpc_network" "my-net" {
  description = "Network for Kafka private sync to S3 bucket"
  name        = "my-private-network"
}

resource "yandex_vpc_subnet" "my-subnet" {
  description    = "Subnet in the ru-central1-a availability zone"
  name           = local.subnet_name
  zone           = local.subnet_zone
  network_id     = yandex_vpc_network.my-net.id
  v4_cidr_blocks = [local.zone_a_v4_cidr_blocks]
}

resource "yandex_vpc_private_endpoint" "my-private-ep" {
  name        = "object-storage-private-endpoint"
  description = "Private endpoint for S3 bucket"

  network_id = yandex_vpc_network.my-net.id

  object_storage {}

  dns_options {
    private_dns_records_enabled = true
  }

  endpoint_address {
    subnet_id = yandex_vpc_subnet.my-subnet.id
  }
}

resource "yandex_vpc_security_group" "my-sg" {
  description = "Security group for the Managed Apache Kafka cluster and VM"
  name        = local.sg_name
  network_id  = yandex_vpc_network.my-net.id

  # Incoming traffic to Apache Kafka cluster
  ingress {
    description    = local.port1_description
    port           = local.allowed_port1
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Incoming traffic to Apache Kafka cluster
  ingress {
    description    = local.port1_description
    port           = local.allowed_port2
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Incoming traffic to VM
  ingress {
    description    = "SSH to VM in the same network"
    port           = local.allowed_port_ssh
    protocol       = "TCP"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  # Outcoming traffic rules
  egress {
    description    = "Allow all outgoing traffic"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
    from_port      = 0
    to_port        = 65535
  }
}

# Create a service account
resource "yandex_iam_service_account" "storage-sa" {
  name      = local.s3_sa_name
  folder_id = data.yandex_iam_service_account.tf-account.folder_id
}

resource "yandex_iam_service_account_static_access_key" "sa-static-key" {
  description        = "SA static key for S3 Sink connector and bucket policy"
  service_account_id = yandex_iam_service_account.storage-sa.id
}

# Create the Yandex Object Storage bucket
resource "yandex_storage_bucket" "topic-bucket" {
  bucket   = local.bucket_name
  max_size = 10737418240 # Bytes
}

resource "yandex_storage_bucket_iam_binding" "users-admins" {
  bucket = local.bucket_name
  role   = "storage.admin"
  members = [
    "serviceAccount:${yandex_iam_service_account.storage-sa.id}"
  ]
  depends_on = [
    yandex_storage_bucket.topic-bucket
  ]
}

# Access policy to the bucket from the private endpoint only
resource "yandex_storage_bucket_policy" "my-policy" {
  bucket     = local.bucket_name
  access_key = yandex_iam_service_account_static_access_key.sa-static-key.access_key
  secret_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key

  policy = jsonencode({
    "Version" = "2012-10-17",
    "Statement" = [{
      "Effect"    = "Allow",
      "Principal" = "*",
      "Action"    = "*",
      "Resource" = [
        "arn:aws:s3:::${local.bucket_name}/*",
        "arn:aws:s3:::${local.bucket_name}"
      ],
      "Condition" = {
        "StringEquals" = {
          "yc:private-endpoint-id" : yandex_vpc_private_endpoint.my-private-ep.id
        }
      }
      },
      {
        "Effect" = "Allow",
        "Principal" = {
          CanonicalUser = data.yandex_iam_service_account.tf-account.service_account_id
        },
        "Action" = "*",
        "Resource" = [
          "arn:aws:s3:::${local.bucket_name}/*",
          "arn:aws:s3:::${local.bucket_name}"
        ]
      }
    ]
  })
}

resource "yandex_mdb_kafka_cluster" "mkf-cluster" {
  description        = local.mkf_cluster_description
  environment        = local.mkf_environment
  name               = local.mkf_cluster_name
  network_id         = yandex_vpc_network.my-net.id
  subnet_ids         = [yandex_vpc_subnet.my-subnet.id]
  security_group_ids = [yandex_vpc_security_group.my-sg.id]

  config {
    brokers_count    = 1
    version          = local.mkf_version
    zones            = [local.subnet_zone]
    assign_public_ip = true
    kafka {
      resources {
        disk_size          = 10 # GB
        disk_type_id       = "network-ssd"
        resource_preset_id = "s2.micro" # 2 vCPU, 8 GB RAM
      }
    }
  }
  maintenance_window {
    type = "ANYTIME"
  }
}

resource "yandex_mdb_kafka_topic" "my-topic" {
  cluster_id         = yandex_mdb_kafka_cluster.mkf-cluster.id
  name               = local.mkf_topic_name
  partitions         = 2
  replication_factor = 1
}

resource "yandex_mdb_kafka_user" "mkf-user" {
  cluster_id = yandex_mdb_kafka_cluster.mkf-cluster.id
  name       = local.mkf_username
  password   = local.mkf_user_password
  permission {
    topic_name = yandex_mdb_kafka_topic.my-topic.name
    role       = "ACCESS_ROLE_PRODUCER"
  }
}

# Connector S3 Sink for data synchronization with the bucket
resource "yandex_mdb_kafka_connector" "pe-storage-connector" {
  cluster_id = yandex_mdb_kafka_cluster.mkf-cluster.id
  name       = "pe-storage-connector"
  tasks_max  = 1
  properties = {
    "key.converter" : "org.apache.kafka.connect.storage.StringConverter",
    "value.converter" : "org.apache.kafka.connect.converters.ByteArrayConverter",
    "format.output.fields.value.encoding" : "none"
  }
  connector_config_s3_sink {
    topics                = yandex_mdb_kafka_topic.my-topic.name
    file_compression_type = "none"
    file_max_records      = 2000
    s3_connection {
      bucket_name = local.bucket_name
      external_s3 {
        endpoint          = "storage.pe.yandexcloud.net"
        access_key_id     = yandex_iam_service_account_static_access_key.sa-static-key.access_key
        secret_access_key = yandex_iam_service_account_static_access_key.sa-static-key.secret_key
      }
    }
  }
}

resource "yandex_compute_instance" "vm-1" {
  name        = local.vm_name
  zone        = local.subnet_zone
  platform_id = "standard-v2"

  resources {
    cores  = 2
    memory = 4
  }

  boot_disk {
    initialize_params {
      image_id = local.vm_image_id
      size     = 10 # GB
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.my-subnet.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.my-sg.id]
  }

  metadata = {
    ssh-keys = "${local.vm_username}:${file(local.vm_ssh_key)}"
  }
}
