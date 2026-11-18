const db = require('./db');

module.exports = async function callWithOutputParameters(callSql, params, outputSql) {
    const conn = await db.getConnection();
    try {
        await conn.query(callSql, params);
        const [rows] = await conn.query(outputSql);
        return rows[0];
    } finally {
        conn.release();
    }
};
