import os
import time
import sqlite3
from flask import Flask, request, jsonify
from flask_cors import CORS
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from google import genai
from google.genai import types

app = Flask(__name__)
CORS(app)

# CONFIGURATION
UPLOAD_FOLDER = 'static/uploads'
os.makedirs(UPLOAD_FOLDER, exist_ok=True)
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# INITIALIZE GOOGLE AI CLIENT
# Replace with your actual API Key or set as environment variable
GEMINI_API_KEY ="AQ.Ab8RN6L38tUETkvV4SAi0rlRfhjOSsCvSlmuBI8BhNbiU_pqiQ"
ADMIN_KEY = os.environ.get("ADMIN_KEY", "MyFallbackKey2026!")
client = genai.Client(api_key=GEMINI_API_KEY, http_options={'api_version': 'v1alpha'})

# DATABASE SETUP
def init_db():
    conn = sqlite3.connect('users.db')
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS users 
                 (id INTEGER PRIMARY KEY AUTOINCREMENT, email TEXT UNIQUE, password TEXT, 
                  trials INTEGER DEFAULT 5, tier TEXT DEFAULT 'free')''')
    conn.commit()
    conn.close()

init_db()

# === AUTH ROUTES ===

@app.route('/auth/register', methods=['POST'])
def register():
    data = request.json
    email = data.get('email')
    password = generate_password_hash(data.get('password'))
    
    try:
        conn = sqlite3.connect('users.db')
        c = conn.cursor()
        c.execute("INSERT INTO users (email, password) VALUES (?, ?)", (email, password))
        conn.commit()
        return jsonify({'success': True, 'message': 'User registered'})
    except:
        return jsonify({'success': False, 'message': 'User already exists'}), 400

@app.route('/auth/login', methods=['POST'])
def login():
    data = request.json
    conn = sqlite3.connect('users.db')
    conn.row_factory = sqlite3.Row
    c = conn.cursor()
    user = c.execute("SELECT * FROM users WHERE email = ?", (data.get('email'),)).fetchone()
    
    if user and check_password_hash(user['password'], data.get('password')):
        return jsonify({
            'success': True, 
            'user': {
                'user_id': str(user['id']), 
                'email': user['email'], 
                'trials_remaining': user['trials'],
                'tier': user['tier']
            }
        })
    return jsonify({'success': False, 'message': 'Invalid credentials'}), 401

# === AI ROUTES ===

@app.route('/analyze/video', methods=['POST'])
def analyze_video():
    user_id = request.form.get('user_id')
    video_file = request.files.get('video')
    
    if video_file:
        filename = secure_filename(video_file.filename)
        path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
        video_file.save(path)

        # Gemini 3 Flash Video Analysis
        with open(path, 'rb') as f:
            video_bytes = f.read()
        
        # Using Gemini 3 Flash for speed and recipe extraction
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=[
                types.Part.from_bytes(data=video_bytes, mime_type="video/mp4"),
                "Extract the full recipe from this video. Return JSON with 'title', 'ingredients' (list), and 'steps' (list)."
            ],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                thinking_config=types.ThinkingConfig(thinking_level="medium")
            )
        )
        return jsonify({'success': True, 'data': response.text})

@app.route('/generate/video', methods=['POST'])
def generate_video():
    data = request.form
    prompt = data.get('prompt')
    
    # Start Veo 3.1 Video Generation
    operation = client.models.generate_videos(
        model="veo-3.1-generate-preview",
        prompt=prompt,
    )

    # Wait for completion (Polling)
    while not operation.done:
        time.sleep(5)
        operation = client.operations.get(operation)

    # In a real app, you'd save this to a cloud bucket like S3 or Firebase
    generated_video = operation.response.generated_videos[0]
    # For now, we return the Google-hosted reference or path
    return jsonify({'success': True, 'video_url': 'Video Generated Successfully'})

@app.route('/fridge/analyze', methods=['POST'])
def analyze_fridge():
    prompt = request.form.get('prompt', 'What meals can I make?')
    media_file = request.files.get('media')
    
    if media_file:
        img_bytes = media_file.read()
        
        # Gemini 3 Flash Analysis with High Resolution for fine details
        response = client.models.generate_content(
            model="gemini-3-flash-preview",
            contents=[
                types.Part.from_bytes(data=img_bytes, mime_type="image/jpeg"),
                prompt
            ],
            config=types.GenerateContentConfig(
                thinking_config=types.ThinkingConfig(thinking_level="high")
            )
        )
        # Mocking the structured response expected by your Flutter app
        return jsonify({
            'success': True, 
            'data': {
                'meals': [response.text],
                'items': ["Detected ingredients based on image"],
                'message': "Analysis complete"
            }
        })

if __name__ == '__main__':
    app.run(debug=True, port=5000)