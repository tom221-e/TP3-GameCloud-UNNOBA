import json
import os
import boto3

dynamodb = boto3.resource('dynamodb')

def lambda_handler(event, context):
    table_name = os.environ.get('TABLE_NAME', 'Puntajes')
    table = dynamodb.Table(table_name)
    
    query_params = event.get('queryStringParameters') or {}
    target_juego = query_params.get('juego') if isinstance(query_params, dict) else None
    
    response = table.scan()
    items = response.get('Items', [])
    
    grouped = {}
    for item in items:
        juego = item.get('juego')
        if target_juego and juego != target_juego:
            continue
        if juego not in grouped:
            grouped[juego] = []
        grouped[juego].append({
            'jugador': item.get('jugador'),
            'puntaje': int(item.get('puntaje', 0))
        })
    
    result = {}
    for juego, players in grouped.items():
        players_sorted = sorted(players, key=lambda x: x['puntaje'], reverse=True)
        result[juego] = players_sorted[:10]
        
    return {
        'statusCode': 200,
        'headers': {'Content-Type': 'application/json', 'Access-Control-Allow-Origin': '*'},
        'body': json.dumps(result)
    }
