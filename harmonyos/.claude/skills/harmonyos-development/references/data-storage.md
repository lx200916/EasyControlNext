# Data Storage — preferences, relationalStore, fileIo

## relationalStore (SQLite)

```ts
import { relationalStore } from '@kit.ArkData'
import { common } from '@kit.AbilityKit'

// Init (call in aboutToAppear / UIAbility.onCreate)
const store = await relationalStore.getRdbStore(ctx, {
  name: 'my_db.db',
  securityLevel: relationalStore.SecurityLevel.S1
})
await store.executeSql('CREATE TABLE IF NOT EXISTS records (...)')

// Insert
const values: relationalStore.ValuesBucket = { id: '1', title: 'Hello' }
await store.insert('records', values)

// Query (ordered)
const predicates = new relationalStore.RdbPredicates('records')
predicates.orderByDesc('timestamp')
const rs = await store.query(predicates, ['id', 'title', 'timestamp'])
while (rs.goToNextRow()) {
  const id = rs.getString(rs.getColumnIndex('id'))
}
rs.close()

// Update
const predicates2 = new relationalStore.RdbPredicates('records')
predicates2.equalTo('id', '1')
await store.update({ title: 'Updated' }, predicates2)

// Delete
const predicates3 = new relationalStore.RdbPredicates('records')
predicates3.equalTo('id', '1')
await store.delete(predicates3)
```

## preferences (key-value settings)

```ts
import { preferences } from '@kit.ArkData'

const store = await preferences.getPreferences(ctx, 'user_settings')
// Read (with default)
const val = (await store.get('sort_order', 'time_desc')) as string
// Write + flush
await store.put('sort_order', 'time_asc')
await store.flush()
```

## fileIo — application file read/write

Core file operations via `@kit.CoreFileKit`. All paths should come from Context properties (filesDir, cacheDir, etc.).

```ts
import { fileIo as fs } from '@kit.CoreFileKit';

const context = getContext(this);

// Write a file
const filePath = context.filesDir + '/data.json';
const file = fs.openSync(filePath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
fs.writeSync(file.fd, JSON.stringify({ key: 'value' }));
fs.closeSync(file);

// Read a file
const readFile = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
const buf = new ArrayBuffer(4096);
const readLen = fs.readSync(readFile.fd, buf);
const content = String.fromCharCode(...new Uint8Array(buf.slice(0, readLen)));
fs.closeSync(readFile);

// Check existence
const exists = fs.accessSync(filePath);

// List directory
const entries = fs.listFileSync(context.filesDir);

// Copy file
fs.copyFileSync(filePath, context.cacheDir + '/data_backup.json');

// Delete file
fs.unlinkSync(filePath);

// Stat file (size, mtime)
const stat = fs.statSync(filePath);
console.info(`size: ${stat.size}, mtime: ${stat.mtime}`);
```

### Read file from Picker URI

```ts
// After picker returns a URI (temporary read-only permission)
const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
const buf = new ArrayBuffer(4096);
const len = fs.readSync(file.fd, buf);
fs.closeSync(file);
```
