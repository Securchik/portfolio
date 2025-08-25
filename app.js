const express = require('express');
const axios = require('axios');
const os = require('os');
require('dotenv').config();

const app = express();
const port = process.env.SERVER_PORT || 3000;

app.get('/', (req, res) => {
    const hostName = os.hostname();
    res.status(200).send(`Host name: ${hostName}\n`);
});

app.get('/health', (req, res) => {
    res.status(200).send(`OK\n`);
});

app.get('/nginx', async (req, res) => {
    const proxyUrl = process.env.NGINX_URL;
    if (!proxyUrl) {
        res.status(500).send("NGINX_URL environment variable is not set\n");
        return;
    }
    try {
        const response = await axios.get(proxyUrl);
        const hostName = os.hostname();
        const finalResponse = `Proxy through ${hostName}: ${response.data}\n`;
        res.status(200).send(finalResponse);
    } catch (error) {
        res.status(500).send(`Failed to proxy request: ${error.message}\n`);
    }
});

app.use((req, res) => {
    res.status(404).send("Not Found\n");
});

app.listen(port, () => {
    console.log(`Starting server on port ${port}`);
});
