terraform {
  required_providers {
    azurerm = {
        source = "hashicorp/azurerm"
        version = ">= 2.99.0"
    }
  }
}

provider "azurerm" {
    skip_provider_registration = true
features {
}  
}

resource "azurerm_resource_group" "Feelit" {
  name     = "Feelit"
  location = "East US"
}

resource "azurerm_resource_group" "Feelit02" {
  name     = "Feelit02"
  location = "East US"
}

resource "azurerm_virtual_network" "Infiniband" {
  name                = "Infiniband"
  location            = azurerm_resource_group.Feelit.location
  resource_group_name = azurerm_resource_group.Feelit.name
  address_space       = ["10.0.0.0/16"]
}

resource "azurerm_subnet" "vinfiniband" {
  name                 = "vinfiniband"
  resource_group_name  = azurerm_resource_group.Feelit.name
  virtual_network_name = azurerm_virtual_network.Infiniband.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_public_ip" "IP_publico" {
  name                = "IP_publico"
  resource_group_name = azurerm_resource_group.Feelit.name
  location            = azurerm_resource_group.Feelit.location
  allocation_method   = "Static"
  
  tags = {
    turma = "veloz"
    Infra = "Zica"
  }
}

resource "azurerm_network_interface" "vinf_nic" {
  name                = "vinf_nic"
  location            = azurerm_resource_group.Feelit.location
  resource_group_name = azurerm_resource_group.Feelit.name

  ip_configuration {
    name                            = "internal"
    subnet_id                       = azurerm_subnet.vinfiniband.id
    private_ip_address_allocation   = "Dynamic"
    public_ip_address_id            = azurerm_public_ip.IP_publico.id
  }
}

resource "azurerm_network_security_group" "Protegendo" {
  name                = "Protegendo"
  location            = azurerm_resource_group.Feelit.location
  resource_group_name = azurerm_resource_group.Feelit.name

  security_rule {
    name                       = "SSH"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "Web"
    priority                   = 101
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "80"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_interface_security_group_association" "ng-nic-assoc" {
  network_interface_id      = azurerm_network_interface.vinf_nic.id
  network_security_group_id = azurerm_network_security_group.Protegendo.id
}

resource "tls_private_key" "private-key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_file" "private_key" {
  content         = tls_private_key.private-key.private_key_pem
  filename        = "key.pem"
  file_permission = "0600"
}

resource "azurerm_linux_virtual_machine" "Instancia" {
  name                = "Instancia"
  resource_group_name = azurerm_resource_group.Feelit.name
  location            = azurerm_resource_group.Feelit.location
  size                = "Standard_B1s"
  admin_username      = "adminuser"
  network_interface_ids = [
    azurerm_network_interface.vinf_nic.id
  ]

  admin_ssh_key {
    username   = "adminuser"
    public_key = tls_private_key.private-key.public_key_openssh
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "UbuntuServer"
    sku       = "16.04-LTS"
    version   = "latest"
  }

  depends_on = [
    local_file.private_key
  ]
}

data "azurerm_public_ip" "data-IP_publico" {
  name = azurerm_public_ip.IP_publico.name
  resource_group_name = azurerm_resource_group.Feelit.name
}

resource "null_resource" "install-nginx" {
  triggers = {
    order = azurerm_linux_virtual_machine.Instancia.id
  }

  connection {
    type = "ssh"
    host = data.azurerm_public_ip.data-IP_publico.ip_address
    user = "adminuser"
    private_key = tls_private_key.private-key.private_key_pem
  }

  provisioner "remote-exec" {
    inline = [
      "sudo apt update",
      "sudo apt install -y nginx"
    ]
  }

  depends_on = [
    azurerm_linux_virtual_machine.Instancia
  ]
}