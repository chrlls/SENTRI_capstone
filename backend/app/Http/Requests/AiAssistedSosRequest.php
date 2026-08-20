<?php

namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class AiAssistedSosRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    public function rules(): array
    {
        return [
            'latitude' => ['required', 'numeric', 'between:-90,90'],
            'longitude' => ['required', 'numeric', 'between:-180,180'],
            // 'mimetypes' (detected content, not extension) mirrors how
            // ai-service/main.py checks UploadFile.content_type — reject
            // here rather than forward a request FastAPI will 400 anyway.
            'audio' => [
                'required',
                'file',
                'mimetypes:audio/wav,audio/x-wav,audio/wave,audio/mpeg,audio/mp3,audio/mp4,audio/m4a,audio/x-m4a,audio/ogg,audio/webm',
                'max:10240',
            ],
        ];
    }
}
