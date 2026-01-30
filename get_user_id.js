const sqlite3 = require('sqlite3').verbose();
const db = new sqlite3.Database('/home/node/.n8n/database.sqlite', sqlite3.OPEN_READONLY);

db.get('SELECT id, email FROM user LIMIT 1', (err, row) => {
    if (err) {
        console.error('Error:', err);
        process.exit(1);
    }
    if (row) {
        console.log(row.id);
    } else {
        console.error('No users found');
        process.exit(1);
    }
    db.close();
});
