import { listContacts, saveContact } from '../server/src/db/contacts.js';
import { buildSearchColumns, computeContactEmbedding, embeddingTextOf } from '../server/src/services/embedding.js';

/**
 * 重算全库的检索列与向量。
 * 改过嵌入口径（比如从「当前值 + 历史值」改成「只嵌当前值」）之后跑一次，
 * 否则老数据还是旧口径算出来的向量。
 */
const contacts = await listContacts();

if (!contacts.length) {
  console.log('库里没有联系人，无需重算。');
  process.exit(0);
}

for (const contact of contacts) {
  const columns = buildSearchColumns(contact);
  const embedding = await computeContactEmbedding(contact);
  await saveContact({ ...contact, ...columns, embedding });
  console.log(`${contact.name}｜${embedding ? '已重算' : '嵌入失败，未写入向量'}｜${embeddingTextOf(contact)}`);
}

console.log(`共 ${contacts.length} 人重算完毕。`);
process.exit(0);
