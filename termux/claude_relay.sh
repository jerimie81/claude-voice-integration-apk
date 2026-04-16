#!/data/data/com.termux/files/usr/bin/bash

# Configuration: Update this with your PC's IP address.
PC_IP="YOUR_PC_IP_HERE"
PC_PORT="5000"

# Capture the input query from command arguments
QUERY="$*"

# Check if query is empty
if [ -z "$QUERY" ]; then
    echo "No query provided."
    exit 1
fi

# Relay the query to the PC server via HTTP POST
curl -s -X POST -d "query=$QUERY" "http://${PC_IP}:${PC_PORT}/claude"

# Optional: Output the response back to Termux for debugging
if [ $? -eq 0 ]; then
    echo "Command successfully relayed to PC."
else
    echo "Failed to relay command to PC. Ensure server is running and IP is correct."
fi
