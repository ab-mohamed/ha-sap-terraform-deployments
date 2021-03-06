locals {
  bastion_count      = var.common_variables["bastion_enabled"] ? 1 : 0
  private_ip_address = var.bastion_srv_ip
  bastion_public_key = var.common_variables["bastion_public_key"] != "" ? var.common_variables["bastion_public_key"] : var.common_variables["public_key"]
  create_data_volumes        = var.common_variables["bastion_enabled"] && var.bastion_data_disk_type == "volume" ? true : false
}

resource "openstack_networking_floatingip_v2" "bastion" {
  count      = local.bastion_count
  pool       = var.floatingip_pool
  depends_on = [var.router_interface_1]
}

resource "openstack_compute_floatingip_associate_v2" "bastion" {
  floating_ip = openstack_networking_floatingip_v2.bastion.0.address
  instance_id = openstack_compute_instance_v2.bastion.0.id
}

resource "openstack_networking_port_v2" "bastion" {
  count = local.bastion_count
  name  = "${var.common_variables["deployment_name"]}-bastion-port-${count.index + 1}"

  network_id     = var.network_id
  admin_state_up = "true"
  fixed_ip {
    subnet_id  = var.network_subnet_id
    ip_address = local.private_ip_address
  }
  security_group_ids = [var.firewall_external, var.firewall_internal]
}

resource "openstack_compute_keypair_v2" "key_terraform_bastion" {
  name       = "terraform_bastion"
  public_key = local.bastion_public_key
  # public_key = var.bastion_public_key
}

data "template_file" "userdata_bastion" {
  template = <<CLOUDCONFIG
#cloud-config

cloud_config_modules:
  - resolv_conf

manage_resolv_conf: true

resolv_conf:
  nameservers: ['8.8.4.4', '8.8.8.8']

users:
  - name: sles
    sudo: [ "ALL=(ALL) NOPASSWD:ALL" ]
    shell: /bin/bash
    # you could set a password here, default is just key login
    # lock_passwd: false
    # plain_text_passwd: 'SecurePassword'
    ssh-authorized-keys:
    - ${local.bastion_public_key}

runcmd:
- |
  # add any command here
  # echo "any command"

CLOUDCONFIG
}

resource "openstack_blockstorage_volume_v3" "data" {
  # only deploy if bastion_data_disk_type is not empty
  count             = local.create_data_volumes ? 1 : 0
  name              = "${var.common_variables["deployment_name"]}-bastion-data-${count.index}"
  size              = var.bastion_data_disk_size
  availability_zone = var.region
  enable_online_resize = true
}

resource "openstack_compute_volume_attach_v2" "data_attached" {
  count       = local.create_data_volumes ? 1 : 0
  instance_id = openstack_compute_instance_v2.bastion.*.id[count.index]
  volume_id   = openstack_blockstorage_volume_v3.data.*.id[count.index]
}

resource "openstack_compute_instance_v2" "bastion" {
  count        = local.bastion_count
  name         = "${var.common_variables["deployment_name"]}-bastion"
  flavor_name  = var.bastion_flavor
  image_id     = var.os_image
  config_drive = true
  user_data    = data.template_file.userdata_bastion.rendered
  key_pair     = "terraform_bastion"
  depends_on   = [openstack_networking_port_v2.bastion]
  network {
    port = openstack_networking_port_v2.bastion.0.id
  }
  availability_zone = var.region
}

module "bastion_on_destroy" {
  source       = "../../../generic_modules/on_destroy"
  node_count   = local.bastion_count
  instance_ids = openstack_compute_instance_v2.bastion.*.id
  user         = var.common_variables["authorized_user"]
  private_key  = var.common_variables["bastion_private_key"]
  public_ips   = [openstack_compute_floatingip_associate_v2.bastion.floating_ip]
  dependencies = var.on_destroy_dependencies
}
