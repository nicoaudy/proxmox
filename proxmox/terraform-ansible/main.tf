resource "proxmox_vm_qemu" "vm" {
  vmid  = var.vm_id + count.index
  name  = "${var.vm_name}-${count.index}"
  desc  = "A VM for using terraform and cloudinit"
  count = var.vm_count

  # Node name has to be the same name as within the cluster
  # this might not include the FQDN
  target_node = var.target_node

  # The destination resource pool for the new VM
  #    pool = "pool0"

  # The template name to clone this vm from
  clone = var.template

  # Activate QEMU agent for this VM
  agent = 1

  os_type = "cloud-init"
  cores   = var.cores
  sockets = var.sockets
  vcpus   = 0
  cpu     = "host"
  memory  = var.memory
  scsihw  = "virtio-scsi-pci"

  # Setup the disk
  disks {
    ide {
      ide2 {
        cloudinit {
          storage = var.local_storage
        }
      }
    }
    scsi {
      scsi0 {
        disk {
          size              = var.disk_size
          cache             = "writeback"
          storage           = var.local_storage
          #storage_type     = "rbd"
          #iothread         = true
          #discard          = true
          replicate         = true
        }
      }
    }
  }

  # Setup the network interface and assign a vlan tag: 256
  network {
    model  = "virtio"
    bridge = var.network_bridge
    #tag = 256
  }

  # Setup the ip address using cloud-init.
  boot = "order=scsi0"

  ipconfig0 = "ip=dhcp"

  serial {
    id   = 0
    type = "socket"
  }

  lifecycle {
    ignore_changes = [
      network
    ]
  }

  ciuser      = var.user
  cipassword  = var.password

  #sshkeys = local.cloud_init.ssh_public_key
  sshkeys = <<EOF
  ${var.ssh_key}
  EOF
}

resource "null_resource" "create_ansible_inventory" {
  provisioner "local-exec" {
    command = <<-EOT
      cat <<EOL > inventory.ini
      [vms]
      ${join("\n", formatlist("%s ansible_host=%s", proxmox_vm_qemu.vm.*.name, proxmox_vm_qemu.vm.*.default_ipv4_address))}

      [vms:vars]
      ansible_become=true
      ansible_user=${var.user}
      ansible_ssh_private_key_file=${var.private_key}
      ansible_ssh_common_args='-o StrictHostKeyChecking=no'
      EOL
    EOT
  }

  depends_on = [proxmox_vm_qemu.vm]
}

resource "null_resource" "ansible" {
  provisioner "local-exec" {
    command = "sleep 180; ansible-playbook -i inventory.ini playbook.yml"
  }

  depends_on = [
    null_resource.create_ansible_inventory
  ]
}

output "vm_info" {
  value = [
    for vm in proxmox_vm_qemu.vm : {
      name = vm.name
      ip   = vm.default_ipv4_address
    }
  ]
}
