#layer1 784 -> 256
#layer2 256 -> 128
#layer3 128 -> 10

import torch
import torch.nn as nn
import torch.optim as optim
import torchvision

from torchvision import datasets, transforms
from torch.utils.data import DataLoader

device = torch.device( "mps" if torch.backends.mps.is_available() else "cpu")
print(device)


transform = transforms.Compose([
    transforms.ToTensor(),
    transforms.Normalize((0.1307,), (0.3081,))
])

BATCH_SIZE = 256


train_data = torchvision.datasets.MNIST('./data', train=True, download=False, transform=transform)
test_data  = torchvision.datasets.MNIST('./data', train=False, download=False, transform=transform)

train_loader = torch.utils.data.DataLoader(train_data, batch_size=BATCH_SIZE, shuffle=True,  pin_memory=True)
test_loader  = torch.utils.data.DataLoader(test_data,  batch_size=1000, shuffle=False, pin_memory=True)


class MLP(nn.Module):

    def __init__(self):
        super().__init__()

        self.l1 = nn.Linear(784,256)
        self.relu = nn.ReLU()
        self.l2 = nn.Linear(256,128)
        self.l3 = nn.Linear(128,10)

    def forward(self, x):
            x = torch.flatten(x, 1)
            x = self.relu(self.l1(x))
            x = self.relu(self.l2(x))
            x = self.l3(x)
            return x

model = MLP().to(device)

criterion = nn.CrossEntropyLoss()

optimizer = optim.Adam(
    model.parameters(),
    lr=0.001
)

epochs = 10

for epoch in range(epochs):

    model.train()

    running_loss = 0

    for images, labels in train_loader:

        images = images.to(device)
        labels = labels.to(device)

        optimizer.zero_grad()

        outputs = model(images)

        loss = criterion(outputs, labels)

        loss.backward()

        optimizer.step()

        running_loss += loss.item()

    print(f"Epoch {epoch+1}: Loss = {running_loss/len(train_loader):.4f}")


model.eval()

correct = 0
total = 0

with torch.no_grad():

    for images, labels in test_loader:

        images = images.to(device)
        labels = labels.to(device)

        outputs = model(images)

        _, predicted = torch.max(outputs, 1)

        total += labels.size(0)
        correct += (predicted == labels).sum().item()

accuracy = 100 * correct / total

print(f"Test Accuracy: {accuracy:.2f}%")

torch.save(model.state_dict(), 'mlp_mnist.pth')
print("\nModel saved to mlp_mnist.pth")