const { deleteGist } = require("@chainlink/functions-toolkit");

// READ encryptedSecretsUrls.txt
const fs = require("fs");
const path = require("path");
const filePath = path.join(__dirname, "encryptedSecretsUrls.txt");

const fileContents = JSON.parse(fs.readFileSync(filePath, "utf8"));

deleteGist(process.env.GITHUB_API_TOKEN, fileContents.gistURL)
  .then(() => {
    console.log(`\n✅Gist at URL ${fileContents.gistURL} deleted successfully`);
    // delete encryptedSecretsUrls.txt from filepath after deleting the gist
    fs.unlink(filePath, err => {
      if (err) {
        console.error(`Error deleting file: ${err.message}`);
      } else {
        console.log("File deleted successfully");
      }
    });
  })
  .catch(e => console.error("\nerror deleting gist at ", fileContents.gistURL, e));
