
variable "TOKEN" {
  type = string
}
variable "CLOUD_ID" {
  type = string
}
variable "FOLDER_ID" {
  type = string
}
variable "zone" {
  type    = string
  default = "ru-central1-a"
}
variable "image_family" {
  type = string
}
variable "subnet_cidr" {
  type = list(string)
  default = [
    "10.0.0.0/24",
  ]
}
variable "user" {
  type = string
}
variable "ssh_key" {
  type = string
}
