output "paperclip_url" {
  description = "Paperclip web UI URL (available ~3-5 min after first boot)"
  value       = "http://${aws_eip.paperclip.public_ip}:3100"
}

output "public_ip" {
  description = "Elastic IP address of the instance"
  value       = aws_eip.paperclip.public_ip
}

output "ssh_command" {
  description = "SSH command (only applicable if key_name variable is set)"
  value       = "ssh -i ~/.ssh/<your-key>.pem ec2-user@${aws_eip.paperclip.public_ip}"
}
