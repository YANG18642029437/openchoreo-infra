terraform {
  backend "local" {
    path = "../../../.private/terraform-state/homelab.tfstate"
  }
}
