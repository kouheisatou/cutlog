// Web Push の鍵を作る:  npm run vapid
import webpush from 'web-push';

const keys = webpush.generateVAPIDKeys();
console.log('VAPID_PUBLIC_KEY=%s', keys.publicKey);
console.log('VAPID_PRIVATE_KEY=%s', keys.privateKey);
console.log('\n.env に貼り付けてから、cutlog を再起動してください。');
