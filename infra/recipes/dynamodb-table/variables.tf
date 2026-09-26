variable "name" {
  description = "Base table name, for example xenia-demo"
  type        = string
  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]{3,200}$", var.name))
    error_message = "name must be 3 to 200 characters of letters, digits, underscore, dot, or hyphen."
  }
}

variable "name_suffix" {
  description = "Appended as <name>-<suffix>; previews pass pr-<n>"
  type        = string
  default     = ""
}

variable "hash_key" {
  description = "Partition key attribute (string)"
  type        = string
  default     = "pk"
}

variable "range_key" {
  description = "Sort key attribute (string); null for a hash-only table"
  type        = string
  default     = "sk"
  nullable    = true
}

variable "ttl_attribute" {
  description = "Attribute holding an epoch-seconds expiry; null turns TTL off"
  type        = string
  default     = "expires_at"
  nullable    = true
}

variable "point_in_time_recovery" {
  description = "PITR: on for the demo table, off for previews (D15)"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Deletion protection: on for the demo table, off for previews (D15)"
  type        = bool
  default     = true
}