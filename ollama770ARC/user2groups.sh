
ls -l /dev/dri
echo "Adding current user to the video and render groups..."
sudo usermod -aG video,render $USER

ls -l /dev/dri

