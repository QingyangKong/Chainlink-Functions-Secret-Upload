const { SecretsManager, createGist } = require("@chainlink/functions-toolkit");
const ethers = require("ethers");
require("@chainlink/env-enc").config();

const encryptAndUploadSecrets = async () => {
  // hardcoded for Avalanche Fuji
  const routerAddress = "0xA9d587a00A31A52Ed70D6026794a8FC5E2F5dCb0";
  const donId = "fun-avalanche-fuji-1";
  const rpcUrl = process.env.AVALANCHE_FUJI_RPC_URL; // fetch Sepolia RPC URL

  const secrets = { apikey: process.env.SUPABASE_API_KEY };

  // Initialize ethers signer and provider to interact with the contracts onchain
  const privateKey = process.env.PRIVATE_KEY; // fetch PRIVATE_KEY
  if (!privateKey) throw new Error("private key not provided - check your environment variables");

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

  const wallet = new ethers.Wallet(privateKey);
  const signer = wallet.connect(provider); // create ethers signer for signing transactions

  //////// ENCRYPT SECRETS////////

  console.log("\nEncrypting Secrets...");

  // First encrypt secrets and create a gist
  const secretsManager = new SecretsManager({
    signer: signer,
    functionsRouterAddress: routerAddress,
    donId: donId,
  });
  await secretsManager.initialize();

  const encryptedSecretsObj = await secretsManager.encryptSecrets(secrets);

  //////// CREATE GITHUB GIST ////////

  console.log(`Creating gist to store encrypted secrets...`);
  const githubApiToken = process.env.GITHUB_API_TOKEN;
  if (!githubApiToken) throw new Error("githubApiToken not provided - check your environment variables");

  // Create a new GitHub Gist to store the encrypted secrets
  const gistURL = await createGist(githubApiToken, JSON.stringify(encryptedSecretsObj));

  //////// ENCRYPT GIST URL ////////
  console.log(`\n✅Gist created ${gistURL} . Encrypt the URLs..`);
  const encryptedSecretsUrls = await secretsManager.encryptSecretsUrls([gistURL]);

  console.log(`\n✅Secrets encrypted. Encrypted URLs: ${encryptedSecretsUrls}`);

  // Write the encrypted secrets URL to a local file
  const fs = require("fs");
  const path = require("path");

  const filePath = path.join(__dirname, "encryptedSecretsUrls.txt");
  fs.writeFileSync(filePath, JSON.stringify({ encryptedSecretsUrls, gistURL }, null, 2));
  console.log(`\n✅Encrypted secrets URLs written to ${filePath}`);
};

encryptAndUploadSecrets().catch(e => {
  console.error(e);
  process.exit(1);
});
