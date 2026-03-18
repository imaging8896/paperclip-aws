output "paperclip_url" {
  description = "Paperclip web UI URL — open this in your browser after starting the SSH tunnel"
  value       = "http://localhost:3100"
}

output "public_ip" {
  description = "Elastic IP address of the instance"
  value       = aws_eip.paperclip.public_ip
}

output "ssh_tunnel_command" {
  description = "SSH command to forward Paperclip UI to localhost:3100 (requires key_name to be set)"
  value       = "ssh -N -L 3100:localhost:3100 ec2-user@${aws_eip.paperclip.public_ip}"
}

output "ssh_command" {
  description = "SSH command to open an interactive shell (requires key_name to be set)"
  value       = "ssh ec2-user@${aws_eip.paperclip.public_ip}"
}
