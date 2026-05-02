let notes = []

export default function handler(req, res) {
    if (req.method === "POST") {
        notes.push(req.body)
        res.status(200).end()
    } else if (req.method === "GET") {
        res.status(200).json(notes)
    } else {
        res.status(405).end()
    }
} 
