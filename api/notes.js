import { kv } from "@vercel/kv"

export default async function handler(req, res) {
    if (req.method === "POST") {
        const notes = await kv.get("notes") || []
        notes.push(req.body)
        await kv.set("notes", notes)
        res.status(200).end()
    } else if (req.method === "GET") {
        const notes = await kv.get("notes") || []
        res.status(200).json(notes)
    } else {
        res.status(405).end()
    }
}
